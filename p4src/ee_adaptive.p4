/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

/* CONSTANTS */

const bit<16> TYPE_IPV4 = 0x800;
const bit<16> TYPE_INFER = 0x8845;
const bit<8>  TYPE_TCP  = 6;

// #define CONST_MAX_PORTS 	32
// #define CONST_MAX_LABELS 	10
// #define REGISTER_LENGTH 255

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
typedef bit<13> switch_id_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header inference_t {
    bit<126>    val;
    bit<2>      padding_bit;
    bit<48>     enter_time;
    bit<48>     exit_time;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    tos;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  res;
    bit<3>  ecn;
    bit<6>  ctrl;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}


struct headers {
    ethernet_t          ethernet;
    inference_t             inference;
    ipv4_t              ipv4;
    tcp_t               tcp;
    udp_t               udp;
}



struct metadata {
    bit<1> is_ingress_border;
    bit<1> is_egress_border;
    bit<126> early_exit_1;
    bit<126> early_exit_2;
    bit<126> big_number;
    bit<126> small_number;
    bit<1> early_exit_result;
    bit<1> activated_exit_1;
    bit<1> activated_exit_2;
    bit<8> predict;
    bit<13> swid;
}


/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {

        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType){
            TYPE_INFER: parse_inference;
            TYPE_IPV4: ipv4;
            default: accept;
        }
    }

    state parse_inference {
        packet.extract(hdr.inference);
        transition ipv4;
    }

    state ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            17: parse_udp;
            6:  parse_tcp;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition accept;
    }

}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {


    register<bit<126>>(1024) weights_bnn;
    bit<126> bnnInput = 0;
    bit<126> XNOROutput = 0;
    bit<126> NextLayerInput = 0;
    bit<5> output_result = 0;

    bit<4> activated = 0;
    bit<128> m1 = 0x55555555555555555555555555555555;
    bit<128> m2 = 0x33333333333333333333333333333333;
    bit<128> m4 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
    bit<128> m8 = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    bit<128> m16= 0x0000ffff0000ffff0000ffff0000ffff;
    bit<128> m32= 0x00000000ffffffff00000000ffffffff;
    bit<128> m64= 0x0000000000000000ffffffffffffffff;

    bit<16> L4src = 0;
    bit<16> L4dst = 0;

    // input: 5-tuple and packet length + tcp flag (bnn style)
    action BuildInput(){
        bnnInput = ((bit<126>)hdr.ipv4.totalLen)<<8;
        bnnInput = (bnnInput + (bit<126>)hdr.ipv4.protocol)<<32;
        bnnInput = (bnnInput + (bit<126>)hdr.ipv4.srcAddr)<<32;
        bnnInput = (bnnInput + (bit<126>)hdr.ipv4.dstAddr)<<16;
        bnnInput = (bnnInput + (bit<126>)L4src)<<16;
        bnnInput = (bnnInput + (bit<126>)L4dst)<<6;
        bnnInput = bnnInput + (bit<126>)hdr.tcp.ctrl;
    }

    action XNOR(bit<126> weight){
        XNOROutput = weight^bnnInput;
        XNOROutput = ~XNOROutput;
    }

    action XNOR_next(bit<126> weight){
    XNOROutput = weight^NextLayerInput;
    XNOROutput = ~XNOROutput;
    }

    action BitCount(bit<126> bitInput){
        bit<128> x= (bit<128>)bitInput;
	    x = (x & m1 ) + ((x >>  1) & m1 );
	    x = (x & m2 ) + ((x >>  2) & m2 );
	    x = (x & m4 ) + ((x >>  4) & m4 );
	    x = (x & m8 ) + ((x >>  8) & m8 );
	    x = (x & m16) + ((x >> 16) & m16);
	    x = (x & m32) + ((x >> 32) & m32);
        x = (x & m64) + ((x >> 64) & m64);
        activated = (x>63) ? (bit<4>)1 : 0;
        NextLayerInput = NextLayerInput<<1;
        NextLayerInput = NextLayerInput + (bit<126>)activated;

    }

    action BitCount1(bit<126>bitInput){
        bit<128> x= (bit<128>)bitInput;
	    x = (x & m1 ) + ((x >>  1) & m1 );
	    x = (x & m2 ) + ((x >>  2) & m2 );
	    x = (x & m4 ) + ((x >>  4) & m4 );
	    x = (x & m8 ) + ((x >>  8) & m8 );
	    x = (x & m16) + ((x >> 16) & m16);
	    x = (x & m32) + ((x >> 32) & m32);
        x = (x & m64) + ((x >> 64) & m64);
        meta.early_exit_1 = (bit<126>)x;
        meta.activated_exit_1 = (x>63) ? (bit<1>)1 : 0;
        // NextLayerInput = NextLayerInput<<1;
        // NextLayerInput = NextLayerInput + (bit<126>)activated;

    }

    action BitCount2(bit<126> bitInput){
        bit<128> x= (bit<128>)bitInput;
	    x = (x & m1 ) + ((x >>  1) & m1 );
	    x = (x & m2 ) + ((x >>  2) & m2 );
	    x = (x & m4 ) + ((x >>  4) & m4 );
	    x = (x & m8 ) + ((x >>  8) & m8 );
	    x = (x & m16) + ((x >> 16) & m16);
	    x = (x & m32) + ((x >> 32) & m32);
        x = (x & m64) + ((x >> 64) & m64);
        meta.early_exit_2 = (bit<126>)x;
        meta.activated_exit_2 = (x>63) ? (bit<1>)1 : 0;
        // NextLayerInput = NextLayerInput<<1;
        // NextLayerInput = NextLayerInput + (bit<126>)activated;

    }

    action LayerProcess(bit<10> offset, bit<126> input_data){
        bit<126> weight = 0;
        bit<126> weight_sub = 0;
        NextLayerInput = input_data;
        weights_bnn.read(weight_sub, (bit<32>)offset+0);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+1);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+2);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+3);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+4);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+5);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+6);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+7);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+8);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+9);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+10);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+11);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+12);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+13);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+14);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+15);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+16);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+17);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+18);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+19);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+20);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+21);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+22);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+23);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+24);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+25);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+26);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+27);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+28);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+29);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+30);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+31);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+32);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+33);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+34);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+35);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+36);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+37);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+38);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+39);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+40);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+41);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+42);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+43);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+44);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+45);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+46);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+47);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+48);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+49);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+50);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+51);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+52);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+53);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+54);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+55);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+56);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+57);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+58);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+59);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+60);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+61);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+62);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+63);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+64);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+65);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+66);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+67);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+68);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+69);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+70);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+71);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+72);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+73);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+74);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+75);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+76);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+77);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+78);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+79);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+80);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+81);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+82);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+83);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+84);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+85);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+86);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+87);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+88);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+89);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+90);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+91);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+92);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+93);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+94);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+95);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+96);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+97);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+98);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+99);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+100);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+101);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+102);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+103);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+104);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+105);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+106);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+107);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+108);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+109);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+110);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+111);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+112);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+113);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+114);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+115);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+116);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+117);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+118);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+119);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+120);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+121);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+122);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+123);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+124);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+125);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+126);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+127);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+128);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+129);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+130);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+131);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+132);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+133);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+134);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+135);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+136);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+137);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+138);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+139);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+140);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+141);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+142);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+143);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+144);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+145);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+146);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+147);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+148);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+149);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+150);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+151);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+152);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+153);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+154);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+155);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+156);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+157);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+158);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+159);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+160);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+161);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+162);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+163);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+164);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+165);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+166);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+167);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+168);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+169);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+170);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+171);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+172);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+173);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+174);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+175);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+176);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+177);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+178);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+179);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+180);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+181);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+182);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+183);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+184);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+185);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+186);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+187);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+188);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+189);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+190);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+191);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+192);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+193);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+194);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+195);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+196);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+197);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+198);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+199);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+200);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+201);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+202);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+203);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+204);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+205);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+206);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+207);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+208);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+209);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+210);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+211);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+212);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+213);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+214);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+215);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+216);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+217);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+218);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+219);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+220);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+221);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+222);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+223);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+224);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+225);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+226);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+227);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+228);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+229);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+230);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+231);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+232);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+233);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+234);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+235);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+236);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+237);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+238);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+239);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+240);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+241);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+242);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+243);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+244);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+245);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+246);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+247);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+248);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+249);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        weights_bnn.read(weight_sub, (bit<32>)offset+250);
        weight = (bit<126>) weight_sub<<63;
        weights_bnn.read(weight_sub, (bit<32>)offset+251);
        weight = weight + (bit<126>) weight_sub;
        XNOR(weight);
        BitCount(XNOROutput);
        // weights_bnn.read(weight_sub, (bit<32>)offset+252);
        // weight = (bit<126>) weight_sub<<63;
        // weights_bnn.read(weight_sub, (bit<32>)offset+253);
        // weight = weight + (bit<126>) weight_sub;
        // XNOR(weight);
        // BitCount(XNOROutput);
        // weights_bnn.read(weight_sub, (bit<32>)offset+254);
        // weight = (bit<126>) weight_sub<<63;
        // weights_bnn.read(weight_sub, (bit<32>)offset+255);
        // weight = weight + (bit<126>) weight_sub;
        // XNOR(weight);
        // BitCount(XNOROutput);
    }

    action check_switch_id(switch_id_t swid){
        if (swid == 1){
            meta.is_ingress_border = (bit<1>)1;

        }
        if (swid == 3) {
            meta.is_egress_border = (bit<1>)1;
        }
        meta.swid = swid;
    }

    table check_swid {
        actions = {
            check_switch_id;
            NoAction;
        }
        default_action = NoAction();
    }


    action add_inference_header() {
        hdr.inference.setValid();
        hdr.inference.val = 0;
        hdr.ethernet.etherType = TYPE_INFER;
    }

    action drop() {
        mark_to_drop(standard_metadata);
    }


    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;

        standard_metadata.egress_spec = port;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
        }
        default_action = drop;
        size = 128;
    }

    action early_exit_flag(bit<4>confidence) {
        bit<4> c_threshold = 7;
        if (confidence >= c_threshold){
            meta.early_exit_result = 1;

        }
        if (confidence < c_threshold){
            meta.early_exit_result = 0;
        }
    }

    table compute_confidence_1 {
        key = {
            meta.small_number: exact;
            meta.big_number: range;
        }
        actions = {
            early_exit_flag;
        }
        size = 1024;
        const entries = {
            (1, 6..9) : early_exit_flag(6);
            (1, 10..13) : early_exit_flag(7);
            (1, 15..18) : early_exit_flag(8);
            (1, 23..26) : early_exit_flag(9);
            (2, 7..10) : early_exit_flag(6);
            (2, 11..14) : early_exit_flag(7);
            (2, 16..19) : early_exit_flag(8);
            (2, 24..27) : early_exit_flag(9);
            (3, 8..11) : early_exit_flag(6);
            (3, 12..15) : early_exit_flag(7);
            (3, 17..20) : early_exit_flag(8);
            (3, 25..28) : early_exit_flag(9);
            (4, 9..12) : early_exit_flag(6);
            (4, 13..16) : early_exit_flag(7);
            (4, 18..21) : early_exit_flag(8);
            (4, 26..29) : early_exit_flag(9);
            (5, 10..13) : early_exit_flag(6);
            (5, 14..17) : early_exit_flag(7);
            (5, 19..22) : early_exit_flag(8);
            (5, 27..30) : early_exit_flag(9);
            (6, 11..14) : early_exit_flag(6);
            (6, 15..18) : early_exit_flag(7);
            (6, 20..23) : early_exit_flag(8);
            (6, 28..31) : early_exit_flag(9);
            (7, 12..15) : early_exit_flag(6);
            (7, 16..19) : early_exit_flag(7);
            (7, 21..24) : early_exit_flag(8);
            (7, 29..32) : early_exit_flag(9);
            (8, 13..16) : early_exit_flag(6);
            (8, 17..20) : early_exit_flag(7);
            (8, 22..25) : early_exit_flag(8);
            (8, 30..33) : early_exit_flag(9);
            (9, 14..17) : early_exit_flag(6);
            (9, 18..21) : early_exit_flag(7);
            (9, 23..26) : early_exit_flag(8);
            (9, 31..34) : early_exit_flag(9);
            (10, 15..18) : early_exit_flag(6);
            (10, 19..22) : early_exit_flag(7);
            (10, 24..27) : early_exit_flag(8);
            (10, 32..35) : early_exit_flag(9);
            (11, 16..19) : early_exit_flag(6);
            (11, 20..23) : early_exit_flag(7);
            (11, 25..28) : early_exit_flag(8);
            (11, 33..36) : early_exit_flag(9);
            (12, 17..20) : early_exit_flag(6);
            (12, 21..24) : early_exit_flag(7);
            (12, 26..29) : early_exit_flag(8);
            (12, 34..37) : early_exit_flag(9);
            (13, 18..21) : early_exit_flag(6);
            (13, 22..25) : early_exit_flag(7);
            (13, 27..30) : early_exit_flag(8);
            (13, 35..38) : early_exit_flag(9);
            (14, 19..22) : early_exit_flag(6);
            (14, 23..26) : early_exit_flag(7);
            (14, 28..31) : early_exit_flag(8);
            (14, 36..39) : early_exit_flag(9);
            (15, 20..23) : early_exit_flag(6);
            (15, 24..27) : early_exit_flag(7);
            (15, 29..32) : early_exit_flag(8);
            (15, 37..40) : early_exit_flag(9);
            (16, 21..24) : early_exit_flag(6);
            (16, 25..28) : early_exit_flag(7);
            (16, 30..33) : early_exit_flag(8);
            (16, 38..41) : early_exit_flag(9);
            (17, 22..25) : early_exit_flag(6);
            (17, 26..29) : early_exit_flag(7);
            (17, 31..34) : early_exit_flag(8);
            (17, 39..42) : early_exit_flag(9);
            (18, 23..26) : early_exit_flag(6);
            (18, 27..30) : early_exit_flag(7);
            (18, 32..35) : early_exit_flag(8);
            (18, 40..43) : early_exit_flag(9);
            (19, 24..27) : early_exit_flag(6);
            (19, 28..31) : early_exit_flag(7);
            (19, 33..36) : early_exit_flag(8);
            (19, 41..44) : early_exit_flag(9);
            (20, 25..28) : early_exit_flag(6);
            (20, 29..32) : early_exit_flag(7);
            (20, 34..37) : early_exit_flag(8);
            (20, 42..45) : early_exit_flag(9);
            (21, 26..29) : early_exit_flag(6);
            (21, 30..33) : early_exit_flag(7);
            (21, 35..38) : early_exit_flag(8);
            (21, 43..46) : early_exit_flag(9);
            (22, 27..30) : early_exit_flag(6);
            (22, 31..34) : early_exit_flag(7);
            (22, 36..39) : early_exit_flag(8);
            (22, 44..47) : early_exit_flag(9);
            (23, 28..31) : early_exit_flag(6);
            (23, 32..35) : early_exit_flag(7);
            (23, 37..40) : early_exit_flag(8);
            (23, 45..48) : early_exit_flag(9);
            (24, 29..32) : early_exit_flag(6);
            (24, 33..36) : early_exit_flag(7);
            (24, 38..41) : early_exit_flag(8);
            (24, 46..49) : early_exit_flag(9);
            (25, 30..33) : early_exit_flag(6);
            (25, 34..37) : early_exit_flag(7);
            (25, 39..42) : early_exit_flag(8);
            (25, 47..50) : early_exit_flag(9);
            (26, 31..34) : early_exit_flag(6);
            (26, 35..38) : early_exit_flag(7);
            (26, 40..43) : early_exit_flag(8);
            (26, 48..51) : early_exit_flag(9);
            (27, 32..35) : early_exit_flag(6);
            (27, 36..39) : early_exit_flag(7);
            (27, 41..44) : early_exit_flag(8);
            (27, 49..52) : early_exit_flag(9);
            (28, 33..36) : early_exit_flag(6);
            (28, 37..40) : early_exit_flag(7);
            (28, 42..45) : early_exit_flag(8);
            (28, 50..53) : early_exit_flag(9);
            (29, 34..37) : early_exit_flag(6);
            (29, 38..41) : early_exit_flag(7);
            (29, 43..46) : early_exit_flag(8);
            (29, 51..54) : early_exit_flag(9);
            (30, 35..38) : early_exit_flag(6);
            (30, 39..42) : early_exit_flag(7);
            (30, 44..47) : early_exit_flag(8);
            (30, 52..55) : early_exit_flag(9);
            (31, 36..39) : early_exit_flag(6);
            (31, 40..43) : early_exit_flag(7);
            (31, 45..48) : early_exit_flag(8);
            (31, 53..56) : early_exit_flag(9);
            (32, 37..40) : early_exit_flag(6);
            (32, 41..44) : early_exit_flag(7);
            (32, 46..49) : early_exit_flag(8);
            (32, 54..57) : early_exit_flag(9);
            (33, 38..41) : early_exit_flag(6);
            (33, 42..45) : early_exit_flag(7);
            (33, 47..50) : early_exit_flag(8);
            (33, 55..58) : early_exit_flag(9);
            (34, 39..42) : early_exit_flag(6);
            (34, 43..46) : early_exit_flag(7);
            (34, 48..51) : early_exit_flag(8);
            (34, 56..59) : early_exit_flag(9);
            (35, 40..43) : early_exit_flag(6);
            (35, 44..47) : early_exit_flag(7);
            (35, 49..52) : early_exit_flag(8);
            (35, 57..60) : early_exit_flag(9);
            (36, 41..44) : early_exit_flag(6);
            (36, 45..48) : early_exit_flag(7);
            (36, 50..53) : early_exit_flag(8);
            (36, 58..61) : early_exit_flag(9);
            (37, 42..45) : early_exit_flag(6);
            (37, 46..49) : early_exit_flag(7);
            (37, 51..54) : early_exit_flag(8);
            (37, 59..62) : early_exit_flag(9);
            (38, 43..46) : early_exit_flag(6);
            (38, 47..50) : early_exit_flag(7);
            (38, 52..55) : early_exit_flag(8);
            (38, 60..63) : early_exit_flag(9);
            (39, 44..47) : early_exit_flag(6);
            (39, 48..51) : early_exit_flag(7);
            (39, 53..56) : early_exit_flag(8);
            (39, 61..64) : early_exit_flag(9);
            (40, 45..48) : early_exit_flag(6);
            (40, 49..52) : early_exit_flag(7);
            (40, 54..57) : early_exit_flag(8);
            (40, 62..65) : early_exit_flag(9);
            (41, 46..49) : early_exit_flag(6);
            (41, 50..53) : early_exit_flag(7);
            (41, 55..58) : early_exit_flag(8);
            (41, 63..66) : early_exit_flag(9);
            (42, 47..50) : early_exit_flag(6);
            (42, 51..54) : early_exit_flag(7);
            (42, 56..59) : early_exit_flag(8);
            (42, 64..67) : early_exit_flag(9);
            (43, 48..51) : early_exit_flag(6);
            (43, 52..55) : early_exit_flag(7);
            (43, 57..60) : early_exit_flag(8);
            (43, 65..68) : early_exit_flag(9);
            (44, 49..52) : early_exit_flag(6);
            (44, 53..56) : early_exit_flag(7);
            (44, 58..61) : early_exit_flag(8);
            (44, 66..69) : early_exit_flag(9);
            (45, 50..53) : early_exit_flag(6);
            (45, 54..57) : early_exit_flag(7);
            (45, 59..62) : early_exit_flag(8);
            (45, 67..70) : early_exit_flag(9);
            (46, 51..54) : early_exit_flag(6);
            (46, 55..58) : early_exit_flag(7);
            (46, 60..63) : early_exit_flag(8);
            (46, 68..71) : early_exit_flag(9);
            (47, 52..55) : early_exit_flag(6);
            (47, 56..59) : early_exit_flag(7);
            (47, 61..64) : early_exit_flag(8);
            (47, 69..72) : early_exit_flag(9);
            (48, 53..56) : early_exit_flag(6);
            (48, 57..60) : early_exit_flag(7);
            (48, 62..65) : early_exit_flag(8);
            (48, 70..73) : early_exit_flag(9);
            (49, 54..57) : early_exit_flag(6);
            (49, 58..61) : early_exit_flag(7);
            (49, 63..66) : early_exit_flag(8);
            (49, 71..74) : early_exit_flag(9);
            (50, 55..58) : early_exit_flag(6);
            (50, 59..62) : early_exit_flag(7);
            (50, 64..67) : early_exit_flag(8);
            (50, 72..75) : early_exit_flag(9);
            (51, 56..59) : early_exit_flag(6);
            (51, 60..63) : early_exit_flag(7);
            (51, 65..68) : early_exit_flag(8);
            (51, 73..76) : early_exit_flag(9);
            (52, 57..60) : early_exit_flag(6);
            (52, 61..64) : early_exit_flag(7);
            (52, 66..69) : early_exit_flag(8);
            (52, 74..77) : early_exit_flag(9);
            (53, 58..61) : early_exit_flag(6);
            (53, 62..65) : early_exit_flag(7);
            (53, 67..70) : early_exit_flag(8);
            (53, 75..78) : early_exit_flag(9);
            (54, 59..62) : early_exit_flag(6);
            (54, 63..66) : early_exit_flag(7);
            (54, 68..71) : early_exit_flag(8);
            (54, 76..79) : early_exit_flag(9);
            (55, 60..63) : early_exit_flag(6);
            (55, 64..67) : early_exit_flag(7);
            (55, 69..72) : early_exit_flag(8);
            (55, 77..80) : early_exit_flag(9);
            (56, 61..64) : early_exit_flag(6);
            (56, 65..68) : early_exit_flag(7);
            (56, 70..73) : early_exit_flag(8);
            (56, 78..81) : early_exit_flag(9);
            (57, 62..65) : early_exit_flag(6);
            (57, 66..69) : early_exit_flag(7);
            (57, 71..74) : early_exit_flag(8);
            (57, 79..82) : early_exit_flag(9);
            (58, 63..66) : early_exit_flag(6);
            (58, 67..70) : early_exit_flag(7);
            (58, 72..75) : early_exit_flag(8);
            (58, 80..83) : early_exit_flag(9);
            (59, 64..67) : early_exit_flag(6);
            (59, 68..71) : early_exit_flag(7);
            (59, 73..76) : early_exit_flag(8);
            (59, 81..84) : early_exit_flag(9);
            (60, 65..68) : early_exit_flag(6);
            (60, 69..72) : early_exit_flag(7);
            (60, 74..77) : early_exit_flag(8);
            (60, 82..85) : early_exit_flag(9);
            (61, 66..69) : early_exit_flag(6);
            (61, 70..73) : early_exit_flag(7);
            (61, 75..78) : early_exit_flag(8);
            (61, 83..86) : early_exit_flag(9);
            (62, 67..70) : early_exit_flag(6);
            (62, 71..74) : early_exit_flag(7);
            (62, 76..79) : early_exit_flag(8);
            (62, 84..87) : early_exit_flag(9);
            (63, 68..71) : early_exit_flag(6);
            (63, 72..75) : early_exit_flag(7);
            (63, 77..80) : early_exit_flag(8);
            (63, 85..88) : early_exit_flag(9);
            (64, 69..72) : early_exit_flag(6);
            (64, 73..76) : early_exit_flag(7);
            (64, 78..81) : early_exit_flag(8);
            (64, 86..89) : early_exit_flag(9);
            (65, 70..73) : early_exit_flag(6);
            (65, 74..77) : early_exit_flag(7);
            (65, 79..82) : early_exit_flag(8);
            (65, 87..90) : early_exit_flag(9);
            (66, 71..74) : early_exit_flag(6);
            (66, 75..78) : early_exit_flag(7);
            (66, 80..83) : early_exit_flag(8);
            (66, 88..91) : early_exit_flag(9);
            (67, 72..75) : early_exit_flag(6);
            (67, 76..79) : early_exit_flag(7);
            (67, 81..84) : early_exit_flag(8);
            (67, 89..92) : early_exit_flag(9);
            (68, 73..76) : early_exit_flag(6);
            (68, 77..80) : early_exit_flag(7);
            (68, 82..85) : early_exit_flag(8);
            (68, 90..93) : early_exit_flag(9);
            (69, 74..77) : early_exit_flag(6);
            (69, 78..81) : early_exit_flag(7);
            (69, 83..86) : early_exit_flag(8);
            (69, 91..94) : early_exit_flag(9);
            (70, 75..78) : early_exit_flag(6);
            (70, 79..82) : early_exit_flag(7);
            (70, 84..87) : early_exit_flag(8);
            (70, 92..95) : early_exit_flag(9);
            (71, 76..79) : early_exit_flag(6);
            (71, 80..83) : early_exit_flag(7);
            (71, 85..88) : early_exit_flag(8);
            (71, 93..96) : early_exit_flag(9);
            (72, 77..80) : early_exit_flag(6);
            (72, 81..84) : early_exit_flag(7);
            (72, 86..89) : early_exit_flag(8);
            (72, 94..97) : early_exit_flag(9);
            (73, 78..81) : early_exit_flag(6);
            (73, 82..85) : early_exit_flag(7);
            (73, 87..90) : early_exit_flag(8);
            (73, 95..98) : early_exit_flag(9);
            (74, 79..82) : early_exit_flag(6);
            (74, 83..86) : early_exit_flag(7);
            (74, 88..91) : early_exit_flag(8);
            (74, 96..99) : early_exit_flag(9);
            (75, 80..83) : early_exit_flag(6);
            (75, 84..87) : early_exit_flag(7);
            (75, 89..92) : early_exit_flag(8);
            (75, 97..100) : early_exit_flag(9);
            (76, 81..84) : early_exit_flag(6);
            (76, 85..88) : early_exit_flag(7);
            (76, 90..93) : early_exit_flag(8);
            (76, 98..101) : early_exit_flag(9);
            (77, 82..85) : early_exit_flag(6);
            (77, 86..89) : early_exit_flag(7);
            (77, 91..94) : early_exit_flag(8);
            (77, 99..102) : early_exit_flag(9);
            (78, 83..86) : early_exit_flag(6);
            (78, 87..90) : early_exit_flag(7);
            (78, 92..95) : early_exit_flag(8);
            (78, 100..103) : early_exit_flag(9);
            (79, 84..87) : early_exit_flag(6);
            (79, 88..91) : early_exit_flag(7);
            (79, 93..96) : early_exit_flag(8);
            (79, 101..104) : early_exit_flag(9);
            (80, 85..88) : early_exit_flag(6);
            (80, 89..92) : early_exit_flag(7);
            (80, 94..97) : early_exit_flag(8);
            (80, 102..105) : early_exit_flag(9);
            (81, 86..89) : early_exit_flag(6);
            (81, 90..93) : early_exit_flag(7);
            (81, 95..98) : early_exit_flag(8);
            (81, 103..106) : early_exit_flag(9);
            (82, 87..90) : early_exit_flag(6);
            (82, 91..94) : early_exit_flag(7);
            (82, 96..99) : early_exit_flag(8);
            (82, 104..107) : early_exit_flag(9);
            (83, 88..91) : early_exit_flag(6);
            (83, 92..95) : early_exit_flag(7);
            (83, 97..100) : early_exit_flag(8);
            (83, 105..108) : early_exit_flag(9);
            (84, 89..92) : early_exit_flag(6);
            (84, 93..96) : early_exit_flag(7);
            (84, 98..101) : early_exit_flag(8);
            (84, 106..109) : early_exit_flag(9);
            (85, 90..93) : early_exit_flag(6);
            (85, 94..97) : early_exit_flag(7);
            (85, 99..102) : early_exit_flag(8);
            (85, 107..110) : early_exit_flag(9);
            (86, 91..94) : early_exit_flag(6);
            (86, 95..98) : early_exit_flag(7);
            (86, 100..103) : early_exit_flag(8);
            (86, 108..111) : early_exit_flag(9);
            (87, 92..95) : early_exit_flag(6);
            (87, 96..99) : early_exit_flag(7);
            (87, 101..104) : early_exit_flag(8);
            (87, 109..112) : early_exit_flag(9);
            (88, 93..96) : early_exit_flag(6);
            (88, 97..100) : early_exit_flag(7);
            (88, 102..105) : early_exit_flag(8);
            (88, 110..113) : early_exit_flag(9);
            (89, 94..97) : early_exit_flag(6);
            (89, 98..101) : early_exit_flag(7);
            (89, 103..106) : early_exit_flag(8);
            (89, 111..114) : early_exit_flag(9);
            (90, 95..98) : early_exit_flag(6);
            (90, 99..102) : early_exit_flag(7);
            (90, 104..107) : early_exit_flag(8);
            (90, 112..115) : early_exit_flag(9);
            (91, 96..99) : early_exit_flag(6);
            (91, 100..103) : early_exit_flag(7);
            (91, 105..108) : early_exit_flag(8);
            (91, 113..116) : early_exit_flag(9);
            (92, 97..100) : early_exit_flag(6);
            (92, 101..104) : early_exit_flag(7);
            (92, 106..109) : early_exit_flag(8);
            (92, 114..117) : early_exit_flag(9);
            (93, 98..101) : early_exit_flag(6);
            (93, 102..105) : early_exit_flag(7);
            (93, 107..110) : early_exit_flag(8);
            (93, 115..118) : early_exit_flag(9);
            (94, 99..102) : early_exit_flag(6);
            (94, 103..106) : early_exit_flag(7);
            (94, 108..111) : early_exit_flag(8);
            (94, 116..119) : early_exit_flag(9);
            (95, 100..103) : early_exit_flag(6);
            (95, 104..107) : early_exit_flag(7);
            (95, 109..112) : early_exit_flag(8);
            (95, 117..120) : early_exit_flag(9);
            (96, 101..104) : early_exit_flag(6);
            (96, 105..108) : early_exit_flag(7);
            (96, 110..113) : early_exit_flag(8);
            (96, 118..121) : early_exit_flag(9);
            (97, 102..105) : early_exit_flag(6);
            (97, 106..109) : early_exit_flag(7);
            (97, 111..114) : early_exit_flag(8);
            (97, 119..122) : early_exit_flag(9);
            (98, 103..106) : early_exit_flag(6);
            (98, 107..110) : early_exit_flag(7);
            (98, 112..115) : early_exit_flag(8);
            (98, 120..123) : early_exit_flag(9);
            (99, 104..107) : early_exit_flag(6);
            (99, 108..111) : early_exit_flag(7);
            (99, 113..116) : early_exit_flag(8);
            (99, 121..124) : early_exit_flag(9);
            (100, 105..108) : early_exit_flag(6);
            (100, 109..112) : early_exit_flag(7);
            (100, 114..117) : early_exit_flag(8);
            (100, 122..125) : early_exit_flag(9);
            (101, 106..109) : early_exit_flag(6);
            (101, 110..113) : early_exit_flag(7);
            (101, 115..118) : early_exit_flag(8);
            (101, 123..126) : early_exit_flag(9);
            (102, 107..110) : early_exit_flag(6);
            (102, 111..114) : early_exit_flag(7);
            (102, 116..119) : early_exit_flag(8);
            (102, 124..127) : early_exit_flag(9);
            (103, 108..111) : early_exit_flag(6);
            (103, 112..115) : early_exit_flag(7);
            (103, 117..120) : early_exit_flag(8);
            (103, 125..128) : early_exit_flag(9);
            (104, 109..112) : early_exit_flag(6);
            (104, 113..116) : early_exit_flag(7);
            (104, 118..121) : early_exit_flag(8);
            (104, 126..129) : early_exit_flag(9);
            (105, 110..113) : early_exit_flag(6);
            (105, 114..117) : early_exit_flag(7);
            (105, 119..122) : early_exit_flag(8);
            (106, 111..114) : early_exit_flag(6);
            (106, 115..118) : early_exit_flag(7);
            (106, 120..123) : early_exit_flag(8);
            (107, 112..115) : early_exit_flag(6);
            (107, 116..119) : early_exit_flag(7);
            (107, 121..124) : early_exit_flag(8);
            (108, 113..116) : early_exit_flag(6);
            (108, 117..120) : early_exit_flag(7);
            (108, 122..125) : early_exit_flag(8);
            (109, 114..117) : early_exit_flag(6);
            (109, 118..121) : early_exit_flag(7);
            (109, 123..126) : early_exit_flag(8);
            (110, 115..118) : early_exit_flag(6);
            (110, 119..122) : early_exit_flag(7);
            (110, 124..127) : early_exit_flag(8);
            (111, 116..119) : early_exit_flag(6);
            (111, 120..123) : early_exit_flag(7);
            (111, 125..128) : early_exit_flag(8);
            (112, 117..120) : early_exit_flag(6);
            (112, 121..124) : early_exit_flag(7);
            (112, 126..129) : early_exit_flag(8);
            (113, 118..121) : early_exit_flag(6);
            (113, 122..125) : early_exit_flag(7);
            (114, 119..122) : early_exit_flag(6);
            (114, 123..126) : early_exit_flag(7);
            (115, 120..123) : early_exit_flag(6);
            (115, 124..127) : early_exit_flag(7);
            (116, 121..124) : early_exit_flag(6);
            (116, 125..128) : early_exit_flag(7);
            (117, 122..125) : early_exit_flag(6);
            (117, 126..129) : early_exit_flag(7);
            (118, 123..126) : early_exit_flag(6);
            (119, 124..127) : early_exit_flag(6);
            (120, 125..128) : early_exit_flag(6);
            (121, 126..129) : early_exit_flag(6);
        }
    }

    table compute_confidence_2 {
        key = {
            meta.small_number: exact;
            meta.big_number: range;
        }
        actions = {
            early_exit_flag;
        }
        size = 1024;
        const entries = {
            (1, 6..9) : early_exit_flag(6);
            (1, 10..13) : early_exit_flag(7);
            (1, 15..18) : early_exit_flag(8);
            (1, 23..26) : early_exit_flag(9);
            (2, 7..10) : early_exit_flag(6);
            (2, 11..14) : early_exit_flag(7);
            (2, 16..19) : early_exit_flag(8);
            (2, 24..27) : early_exit_flag(9);
            (3, 8..11) : early_exit_flag(6);
            (3, 12..15) : early_exit_flag(7);
            (3, 17..20) : early_exit_flag(8);
            (3, 25..28) : early_exit_flag(9);
            (4, 9..12) : early_exit_flag(6);
            (4, 13..16) : early_exit_flag(7);
            (4, 18..21) : early_exit_flag(8);
            (4, 26..29) : early_exit_flag(9);
            (5, 10..13) : early_exit_flag(6);
            (5, 14..17) : early_exit_flag(7);
            (5, 19..22) : early_exit_flag(8);
            (5, 27..30) : early_exit_flag(9);
            (6, 11..14) : early_exit_flag(6);
            (6, 15..18) : early_exit_flag(7);
            (6, 20..23) : early_exit_flag(8);
            (6, 28..31) : early_exit_flag(9);
            (7, 12..15) : early_exit_flag(6);
            (7, 16..19) : early_exit_flag(7);
            (7, 21..24) : early_exit_flag(8);
            (7, 29..32) : early_exit_flag(9);
            (8, 13..16) : early_exit_flag(6);
            (8, 17..20) : early_exit_flag(7);
            (8, 22..25) : early_exit_flag(8);
            (8, 30..33) : early_exit_flag(9);
            (9, 14..17) : early_exit_flag(6);
            (9, 18..21) : early_exit_flag(7);
            (9, 23..26) : early_exit_flag(8);
            (9, 31..34) : early_exit_flag(9);
            (10, 15..18) : early_exit_flag(6);
            (10, 19..22) : early_exit_flag(7);
            (10, 24..27) : early_exit_flag(8);
            (10, 32..35) : early_exit_flag(9);
            (11, 16..19) : early_exit_flag(6);
            (11, 20..23) : early_exit_flag(7);
            (11, 25..28) : early_exit_flag(8);
            (11, 33..36) : early_exit_flag(9);
            (12, 17..20) : early_exit_flag(6);
            (12, 21..24) : early_exit_flag(7);
            (12, 26..29) : early_exit_flag(8);
            (12, 34..37) : early_exit_flag(9);
            (13, 18..21) : early_exit_flag(6);
            (13, 22..25) : early_exit_flag(7);
            (13, 27..30) : early_exit_flag(8);
            (13, 35..38) : early_exit_flag(9);
            (14, 19..22) : early_exit_flag(6);
            (14, 23..26) : early_exit_flag(7);
            (14, 28..31) : early_exit_flag(8);
            (14, 36..39) : early_exit_flag(9);
            (15, 20..23) : early_exit_flag(6);
            (15, 24..27) : early_exit_flag(7);
            (15, 29..32) : early_exit_flag(8);
            (15, 37..40) : early_exit_flag(9);
            (16, 21..24) : early_exit_flag(6);
            (16, 25..28) : early_exit_flag(7);
            (16, 30..33) : early_exit_flag(8);
            (16, 38..41) : early_exit_flag(9);
            (17, 22..25) : early_exit_flag(6);
            (17, 26..29) : early_exit_flag(7);
            (17, 31..34) : early_exit_flag(8);
            (17, 39..42) : early_exit_flag(9);
            (18, 23..26) : early_exit_flag(6);
            (18, 27..30) : early_exit_flag(7);
            (18, 32..35) : early_exit_flag(8);
            (18, 40..43) : early_exit_flag(9);
            (19, 24..27) : early_exit_flag(6);
            (19, 28..31) : early_exit_flag(7);
            (19, 33..36) : early_exit_flag(8);
            (19, 41..44) : early_exit_flag(9);
            (20, 25..28) : early_exit_flag(6);
            (20, 29..32) : early_exit_flag(7);
            (20, 34..37) : early_exit_flag(8);
            (20, 42..45) : early_exit_flag(9);
            (21, 26..29) : early_exit_flag(6);
            (21, 30..33) : early_exit_flag(7);
            (21, 35..38) : early_exit_flag(8);
            (21, 43..46) : early_exit_flag(9);
            (22, 27..30) : early_exit_flag(6);
            (22, 31..34) : early_exit_flag(7);
            (22, 36..39) : early_exit_flag(8);
            (22, 44..47) : early_exit_flag(9);
            (23, 28..31) : early_exit_flag(6);
            (23, 32..35) : early_exit_flag(7);
            (23, 37..40) : early_exit_flag(8);
            (23, 45..48) : early_exit_flag(9);
            (24, 29..32) : early_exit_flag(6);
            (24, 33..36) : early_exit_flag(7);
            (24, 38..41) : early_exit_flag(8);
            (24, 46..49) : early_exit_flag(9);
            (25, 30..33) : early_exit_flag(6);
            (25, 34..37) : early_exit_flag(7);
            (25, 39..42) : early_exit_flag(8);
            (25, 47..50) : early_exit_flag(9);
            (26, 31..34) : early_exit_flag(6);
            (26, 35..38) : early_exit_flag(7);
            (26, 40..43) : early_exit_flag(8);
            (26, 48..51) : early_exit_flag(9);
            (27, 32..35) : early_exit_flag(6);
            (27, 36..39) : early_exit_flag(7);
            (27, 41..44) : early_exit_flag(8);
            (27, 49..52) : early_exit_flag(9);
            (28, 33..36) : early_exit_flag(6);
            (28, 37..40) : early_exit_flag(7);
            (28, 42..45) : early_exit_flag(8);
            (28, 50..53) : early_exit_flag(9);
            (29, 34..37) : early_exit_flag(6);
            (29, 38..41) : early_exit_flag(7);
            (29, 43..46) : early_exit_flag(8);
            (29, 51..54) : early_exit_flag(9);
            (30, 35..38) : early_exit_flag(6);
            (30, 39..42) : early_exit_flag(7);
            (30, 44..47) : early_exit_flag(8);
            (30, 52..55) : early_exit_flag(9);
            (31, 36..39) : early_exit_flag(6);
            (31, 40..43) : early_exit_flag(7);
            (31, 45..48) : early_exit_flag(8);
            (31, 53..56) : early_exit_flag(9);
            (32, 37..40) : early_exit_flag(6);
            (32, 41..44) : early_exit_flag(7);
            (32, 46..49) : early_exit_flag(8);
            (32, 54..57) : early_exit_flag(9);
            (33, 38..41) : early_exit_flag(6);
            (33, 42..45) : early_exit_flag(7);
            (33, 47..50) : early_exit_flag(8);
            (33, 55..58) : early_exit_flag(9);
            (34, 39..42) : early_exit_flag(6);
            (34, 43..46) : early_exit_flag(7);
            (34, 48..51) : early_exit_flag(8);
            (34, 56..59) : early_exit_flag(9);
            (35, 40..43) : early_exit_flag(6);
            (35, 44..47) : early_exit_flag(7);
            (35, 49..52) : early_exit_flag(8);
            (35, 57..60) : early_exit_flag(9);
            (36, 41..44) : early_exit_flag(6);
            (36, 45..48) : early_exit_flag(7);
            (36, 50..53) : early_exit_flag(8);
            (36, 58..61) : early_exit_flag(9);
            (37, 42..45) : early_exit_flag(6);
            (37, 46..49) : early_exit_flag(7);
            (37, 51..54) : early_exit_flag(8);
            (37, 59..62) : early_exit_flag(9);
            (38, 43..46) : early_exit_flag(6);
            (38, 47..50) : early_exit_flag(7);
            (38, 52..55) : early_exit_flag(8);
            (38, 60..63) : early_exit_flag(9);
            (39, 44..47) : early_exit_flag(6);
            (39, 48..51) : early_exit_flag(7);
            (39, 53..56) : early_exit_flag(8);
            (39, 61..64) : early_exit_flag(9);
            (40, 45..48) : early_exit_flag(6);
            (40, 49..52) : early_exit_flag(7);
            (40, 54..57) : early_exit_flag(8);
            (40, 62..65) : early_exit_flag(9);
            (41, 46..49) : early_exit_flag(6);
            (41, 50..53) : early_exit_flag(7);
            (41, 55..58) : early_exit_flag(8);
            (41, 63..66) : early_exit_flag(9);
            (42, 47..50) : early_exit_flag(6);
            (42, 51..54) : early_exit_flag(7);
            (42, 56..59) : early_exit_flag(8);
            (42, 64..67) : early_exit_flag(9);
            (43, 48..51) : early_exit_flag(6);
            (43, 52..55) : early_exit_flag(7);
            (43, 57..60) : early_exit_flag(8);
            (43, 65..68) : early_exit_flag(9);
            (44, 49..52) : early_exit_flag(6);
            (44, 53..56) : early_exit_flag(7);
            (44, 58..61) : early_exit_flag(8);
            (44, 66..69) : early_exit_flag(9);
            (45, 50..53) : early_exit_flag(6);
            (45, 54..57) : early_exit_flag(7);
            (45, 59..62) : early_exit_flag(8);
            (45, 67..70) : early_exit_flag(9);
            (46, 51..54) : early_exit_flag(6);
            (46, 55..58) : early_exit_flag(7);
            (46, 60..63) : early_exit_flag(8);
            (46, 68..71) : early_exit_flag(9);
            (47, 52..55) : early_exit_flag(6);
            (47, 56..59) : early_exit_flag(7);
            (47, 61..64) : early_exit_flag(8);
            (47, 69..72) : early_exit_flag(9);
            (48, 53..56) : early_exit_flag(6);
            (48, 57..60) : early_exit_flag(7);
            (48, 62..65) : early_exit_flag(8);
            (48, 70..73) : early_exit_flag(9);
            (49, 54..57) : early_exit_flag(6);
            (49, 58..61) : early_exit_flag(7);
            (49, 63..66) : early_exit_flag(8);
            (49, 71..74) : early_exit_flag(9);
            (50, 55..58) : early_exit_flag(6);
            (50, 59..62) : early_exit_flag(7);
            (50, 64..67) : early_exit_flag(8);
            (50, 72..75) : early_exit_flag(9);
            (51, 56..59) : early_exit_flag(6);
            (51, 60..63) : early_exit_flag(7);
            (51, 65..68) : early_exit_flag(8);
            (51, 73..76) : early_exit_flag(9);
            (52, 57..60) : early_exit_flag(6);
            (52, 61..64) : early_exit_flag(7);
            (52, 66..69) : early_exit_flag(8);
            (52, 74..77) : early_exit_flag(9);
            (53, 58..61) : early_exit_flag(6);
            (53, 62..65) : early_exit_flag(7);
            (53, 67..70) : early_exit_flag(8);
            (53, 75..78) : early_exit_flag(9);
            (54, 59..62) : early_exit_flag(6);
            (54, 63..66) : early_exit_flag(7);
            (54, 68..71) : early_exit_flag(8);
            (54, 76..79) : early_exit_flag(9);
            (55, 60..63) : early_exit_flag(6);
            (55, 64..67) : early_exit_flag(7);
            (55, 69..72) : early_exit_flag(8);
            (55, 77..80) : early_exit_flag(9);
            (56, 61..64) : early_exit_flag(6);
            (56, 65..68) : early_exit_flag(7);
            (56, 70..73) : early_exit_flag(8);
            (56, 78..81) : early_exit_flag(9);
            (57, 62..65) : early_exit_flag(6);
            (57, 66..69) : early_exit_flag(7);
            (57, 71..74) : early_exit_flag(8);
            (57, 79..82) : early_exit_flag(9);
            (58, 63..66) : early_exit_flag(6);
            (58, 67..70) : early_exit_flag(7);
            (58, 72..75) : early_exit_flag(8);
            (58, 80..83) : early_exit_flag(9);
            (59, 64..67) : early_exit_flag(6);
            (59, 68..71) : early_exit_flag(7);
            (59, 73..76) : early_exit_flag(8);
            (59, 81..84) : early_exit_flag(9);
            (60, 65..68) : early_exit_flag(6);
            (60, 69..72) : early_exit_flag(7);
            (60, 74..77) : early_exit_flag(8);
            (60, 82..85) : early_exit_flag(9);
            (61, 66..69) : early_exit_flag(6);
            (61, 70..73) : early_exit_flag(7);
            (61, 75..78) : early_exit_flag(8);
            (61, 83..86) : early_exit_flag(9);
            (62, 67..70) : early_exit_flag(6);
            (62, 71..74) : early_exit_flag(7);
            (62, 76..79) : early_exit_flag(8);
            (62, 84..87) : early_exit_flag(9);
            (63, 68..71) : early_exit_flag(6);
            (63, 72..75) : early_exit_flag(7);
            (63, 77..80) : early_exit_flag(8);
            (63, 85..88) : early_exit_flag(9);
            (64, 69..72) : early_exit_flag(6);
            (64, 73..76) : early_exit_flag(7);
            (64, 78..81) : early_exit_flag(8);
            (64, 86..89) : early_exit_flag(9);
            (65, 70..73) : early_exit_flag(6);
            (65, 74..77) : early_exit_flag(7);
            (65, 79..82) : early_exit_flag(8);
            (65, 87..90) : early_exit_flag(9);
            (66, 71..74) : early_exit_flag(6);
            (66, 75..78) : early_exit_flag(7);
            (66, 80..83) : early_exit_flag(8);
            (66, 88..91) : early_exit_flag(9);
            (67, 72..75) : early_exit_flag(6);
            (67, 76..79) : early_exit_flag(7);
            (67, 81..84) : early_exit_flag(8);
            (67, 89..92) : early_exit_flag(9);
            (68, 73..76) : early_exit_flag(6);
            (68, 77..80) : early_exit_flag(7);
            (68, 82..85) : early_exit_flag(8);
            (68, 90..93) : early_exit_flag(9);
            (69, 74..77) : early_exit_flag(6);
            (69, 78..81) : early_exit_flag(7);
            (69, 83..86) : early_exit_flag(8);
            (69, 91..94) : early_exit_flag(9);
            (70, 75..78) : early_exit_flag(6);
            (70, 79..82) : early_exit_flag(7);
            (70, 84..87) : early_exit_flag(8);
            (70, 92..95) : early_exit_flag(9);
            (71, 76..79) : early_exit_flag(6);
            (71, 80..83) : early_exit_flag(7);
            (71, 85..88) : early_exit_flag(8);
            (71, 93..96) : early_exit_flag(9);
            (72, 77..80) : early_exit_flag(6);
            (72, 81..84) : early_exit_flag(7);
            (72, 86..89) : early_exit_flag(8);
            (72, 94..97) : early_exit_flag(9);
            (73, 78..81) : early_exit_flag(6);
            (73, 82..85) : early_exit_flag(7);
            (73, 87..90) : early_exit_flag(8);
            (73, 95..98) : early_exit_flag(9);
            (74, 79..82) : early_exit_flag(6);
            (74, 83..86) : early_exit_flag(7);
            (74, 88..91) : early_exit_flag(8);
            (74, 96..99) : early_exit_flag(9);
            (75, 80..83) : early_exit_flag(6);
            (75, 84..87) : early_exit_flag(7);
            (75, 89..92) : early_exit_flag(8);
            (75, 97..100) : early_exit_flag(9);
            (76, 81..84) : early_exit_flag(6);
            (76, 85..88) : early_exit_flag(7);
            (76, 90..93) : early_exit_flag(8);
            (76, 98..101) : early_exit_flag(9);
            (77, 82..85) : early_exit_flag(6);
            (77, 86..89) : early_exit_flag(7);
            (77, 91..94) : early_exit_flag(8);
            (77, 99..102) : early_exit_flag(9);
            (78, 83..86) : early_exit_flag(6);
            (78, 87..90) : early_exit_flag(7);
            (78, 92..95) : early_exit_flag(8);
            (78, 100..103) : early_exit_flag(9);
            (79, 84..87) : early_exit_flag(6);
            (79, 88..91) : early_exit_flag(7);
            (79, 93..96) : early_exit_flag(8);
            (79, 101..104) : early_exit_flag(9);
            (80, 85..88) : early_exit_flag(6);
            (80, 89..92) : early_exit_flag(7);
            (80, 94..97) : early_exit_flag(8);
            (80, 102..105) : early_exit_flag(9);
            (81, 86..89) : early_exit_flag(6);
            (81, 90..93) : early_exit_flag(7);
            (81, 95..98) : early_exit_flag(8);
            (81, 103..106) : early_exit_flag(9);
            (82, 87..90) : early_exit_flag(6);
            (82, 91..94) : early_exit_flag(7);
            (82, 96..99) : early_exit_flag(8);
            (82, 104..107) : early_exit_flag(9);
            (83, 88..91) : early_exit_flag(6);
            (83, 92..95) : early_exit_flag(7);
            (83, 97..100) : early_exit_flag(8);
            (83, 105..108) : early_exit_flag(9);
            (84, 89..92) : early_exit_flag(6);
            (84, 93..96) : early_exit_flag(7);
            (84, 98..101) : early_exit_flag(8);
            (84, 106..109) : early_exit_flag(9);
            (85, 90..93) : early_exit_flag(6);
            (85, 94..97) : early_exit_flag(7);
            (85, 99..102) : early_exit_flag(8);
            (85, 107..110) : early_exit_flag(9);
            (86, 91..94) : early_exit_flag(6);
            (86, 95..98) : early_exit_flag(7);
            (86, 100..103) : early_exit_flag(8);
            (86, 108..111) : early_exit_flag(9);
            (87, 92..95) : early_exit_flag(6);
            (87, 96..99) : early_exit_flag(7);
            (87, 101..104) : early_exit_flag(8);
            (87, 109..112) : early_exit_flag(9);
            (88, 93..96) : early_exit_flag(6);
            (88, 97..100) : early_exit_flag(7);
            (88, 102..105) : early_exit_flag(8);
            (88, 110..113) : early_exit_flag(9);
            (89, 94..97) : early_exit_flag(6);
            (89, 98..101) : early_exit_flag(7);
            (89, 103..106) : early_exit_flag(8);
            (89, 111..114) : early_exit_flag(9);
            (90, 95..98) : early_exit_flag(6);
            (90, 99..102) : early_exit_flag(7);
            (90, 104..107) : early_exit_flag(8);
            (90, 112..115) : early_exit_flag(9);
            (91, 96..99) : early_exit_flag(6);
            (91, 100..103) : early_exit_flag(7);
            (91, 105..108) : early_exit_flag(8);
            (91, 113..116) : early_exit_flag(9);
            (92, 97..100) : early_exit_flag(6);
            (92, 101..104) : early_exit_flag(7);
            (92, 106..109) : early_exit_flag(8);
            (92, 114..117) : early_exit_flag(9);
            (93, 98..101) : early_exit_flag(6);
            (93, 102..105) : early_exit_flag(7);
            (93, 107..110) : early_exit_flag(8);
            (93, 115..118) : early_exit_flag(9);
            (94, 99..102) : early_exit_flag(6);
            (94, 103..106) : early_exit_flag(7);
            (94, 108..111) : early_exit_flag(8);
            (94, 116..119) : early_exit_flag(9);
            (95, 100..103) : early_exit_flag(6);
            (95, 104..107) : early_exit_flag(7);
            (95, 109..112) : early_exit_flag(8);
            (95, 117..120) : early_exit_flag(9);
            (96, 101..104) : early_exit_flag(6);
            (96, 105..108) : early_exit_flag(7);
            (96, 110..113) : early_exit_flag(8);
            (96, 118..121) : early_exit_flag(9);
            (97, 102..105) : early_exit_flag(6);
            (97, 106..109) : early_exit_flag(7);
            (97, 111..114) : early_exit_flag(8);
            (97, 119..122) : early_exit_flag(9);
            (98, 103..106) : early_exit_flag(6);
            (98, 107..110) : early_exit_flag(7);
            (98, 112..115) : early_exit_flag(8);
            (98, 120..123) : early_exit_flag(9);
            (99, 104..107) : early_exit_flag(6);
            (99, 108..111) : early_exit_flag(7);
            (99, 113..116) : early_exit_flag(8);
            (99, 121..124) : early_exit_flag(9);
            (100, 105..108) : early_exit_flag(6);
            (100, 109..112) : early_exit_flag(7);
            (100, 114..117) : early_exit_flag(8);
            (100, 122..125) : early_exit_flag(9);
            (101, 106..109) : early_exit_flag(6);
            (101, 110..113) : early_exit_flag(7);
            (101, 115..118) : early_exit_flag(8);
            (101, 123..126) : early_exit_flag(9);
            (102, 107..110) : early_exit_flag(6);
            (102, 111..114) : early_exit_flag(7);
            (102, 116..119) : early_exit_flag(8);
            (102, 124..127) : early_exit_flag(9);
            (103, 108..111) : early_exit_flag(6);
            (103, 112..115) : early_exit_flag(7);
            (103, 117..120) : early_exit_flag(8);
            (103, 125..128) : early_exit_flag(9);
            (104, 109..112) : early_exit_flag(6);
            (104, 113..116) : early_exit_flag(7);
            (104, 118..121) : early_exit_flag(8);
            (104, 126..129) : early_exit_flag(9);
            (105, 110..113) : early_exit_flag(6);
            (105, 114..117) : early_exit_flag(7);
            (105, 119..122) : early_exit_flag(8);
            (106, 111..114) : early_exit_flag(6);
            (106, 115..118) : early_exit_flag(7);
            (106, 120..123) : early_exit_flag(8);
            (107, 112..115) : early_exit_flag(6);
            (107, 116..119) : early_exit_flag(7);
            (107, 121..124) : early_exit_flag(8);
            (108, 113..116) : early_exit_flag(6);
            (108, 117..120) : early_exit_flag(7);
            (108, 122..125) : early_exit_flag(8);
            (109, 114..117) : early_exit_flag(6);
            (109, 118..121) : early_exit_flag(7);
            (109, 123..126) : early_exit_flag(8);
            (110, 115..118) : early_exit_flag(6);
            (110, 119..122) : early_exit_flag(7);
            (110, 124..127) : early_exit_flag(8);
            (111, 116..119) : early_exit_flag(6);
            (111, 120..123) : early_exit_flag(7);
            (111, 125..128) : early_exit_flag(8);
            (112, 117..120) : early_exit_flag(6);
            (112, 121..124) : early_exit_flag(7);
            (112, 126..129) : early_exit_flag(8);
            (113, 118..121) : early_exit_flag(6);
            (113, 122..125) : early_exit_flag(7);
            (114, 119..122) : early_exit_flag(6);
            (114, 123..126) : early_exit_flag(7);
            (115, 120..123) : early_exit_flag(6);
            (115, 124..127) : early_exit_flag(7);
            (116, 121..124) : early_exit_flag(6);
            (116, 125..128) : early_exit_flag(7);
            (117, 122..125) : early_exit_flag(6);
            (117, 126..129) : early_exit_flag(7);
            (118, 123..126) : early_exit_flag(6);
            (119, 124..127) : early_exit_flag(6);
            (120, 125..128) : early_exit_flag(6);
            (121, 126..129) : early_exit_flag(6);
        }
    }

    // // new table, action
    action predict() {
        // result-> ip filed (ip type of service tos / )
        if (meta.early_exit_1 < meta.early_exit_2) {
            meta.predict = 0;
            meta.big_number = meta.early_exit_2;
            meta.small_number = meta.early_exit_1;
        }
        else {
            meta.predict = 1;
            meta.big_number = meta.early_exit_1;
            meta.small_number = meta.early_exit_2;
        }
        hdr.ipv4.tos = meta.predict;
    }

    action no_early_exit() {
        standard_metadata.egress_spec = 3;
    }
    action yes_early_exit() {
        standard_metadata.egress_spec = 2;
    }

    table early_exiting_1 {
        key = {
            meta.early_exit_result: exact;
        }
        actions = {
            yes_early_exit;
            no_early_exit;
        }
        default_action = no_early_exit;
        size = 1024;
    }
    table early_exiting_2{
        key = {
            meta.early_exit_result: exact;
        }
        actions = {
            yes_early_exit;
            no_early_exit;
        }
        default_action = no_early_exit;
        size = 1024;
    }


    apply {
        check_swid.apply();

        if (hdr.udp.isValid()){
            L4src=hdr.udp.srcPort;
            L4dst=hdr.udp.dstPort;
        }

        if (hdr.tcp.isValid()){
            L4src=hdr.tcp.srcPort;
            L4dst=hdr.tcp.dstPort;
        }
        // add_inference_header();

        if (meta.swid == 1) {
            if (hdr.ipv4.isValid()){
                 add_inference_header();
                 hdr.inference.enter_time = standard_metadata.ingress_global_timestamp;

                 if (hdr.inference.val == 0){
                     BuildInput();

                     LayerProcess(0,bnnInput);
                     //early exit classifier
                     bit<126> weight=0; 
                     bit<126> weight_sub=0; 
                     weights_bnn.read(weight_sub, (bit<32>)252);
                     weight = (bit<126>) weight_sub << 63;
                     weights_bnn.read(weight_sub, (bit<32>)253);
                     weight = weight + (bit<126>) weight_sub;
                     XNOR_next(weight);
                     BitCount1(XNOROutput);
                     weights_bnn.read(weight_sub, (bit<32>)254);
                     weight = (bit<126>) weight_sub << 63;
                     weights_bnn.read(weight_sub, (bit<32>)255);
                     weight = weight + (bit<126>) weight_sub;
                     XNOR_next(weight);
                     BitCount2(XNOROutput);

                    // Check early exit result then early exit or continue
                     predict();
                     compute_confidence_1.apply();                     
                     early_exiting_1.apply();
                     hdr.inference.val = NextLayerInput;
                 }
            }
        }

        else if (hdr.inference.isValid()){

             if (hdr.inference.val != 0){
                bnnInput = hdr.inference.val;
                LayerProcess(0,bnnInput);

                 //early exit classifier
                bit<126> weight=0; 
                bit<126> weight_sub=0; 
                weights_bnn.read(weight_sub, (bit<32>)252);
                weight = (bit<126>) weight_sub << 63;
                weights_bnn.read(weight_sub, (bit<32>)253);
                weight = weight + (bit<126>) weight_sub;
                XNOR_next(weight);
                BitCount1(XNOROutput);
                weights_bnn.read(weight_sub, (bit<32>)254);
                weight = (bit<126>) weight_sub << 63;
                weights_bnn.read(weight_sub, (bit<32>)255);
                weight = weight + (bit<126>) weight_sub;
                XNOR_next(weight);
                BitCount2(XNOROutput);

                // Check early exit result then early exit or continue
                predict();
                compute_confidence_2.apply();
                early_exiting_2.apply();
                hdr.inference.val = NextLayerInput;

      }
        if (meta.swid == 3){
            standard_metadata.egress_spec = 2;
        }
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {


    apply {
        hdr.inference.exit_time = standard_metadata.egress_global_timestamp;
    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {
	update_checksum(
	    hdr.ipv4.isValid(),
            { hdr.ipv4.version,
	      hdr.ipv4.ihl,
              hdr.ipv4.tos,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {

        //parsed headers have to be added again into the packet.
        packet.emit(hdr.ethernet);
        packet.emit(hdr.inference);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

//switch architecture
V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
