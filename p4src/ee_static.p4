/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

/* CONSTANTS */

const bit<16> TYPE_IPV4 = 0x800;
const bit<16> TYPE_INFER = 0x8845;
const bit<8>  TYPE_TCP  = 6;

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
    ethernet_t  ethernet;
    inference_t inference;
    ipv4_t      ipv4;
    tcp_t       tcp;
    udp_t       udp;
}


struct metadata {
    bit<1>   is_ingress_border;
    bit<1>   is_egress_border;
    bit<126> early_exit_1;
    bit<126> early_exit_2;
    bit<1>   early_exit_result;
    bit<1>   activated_exit_1;
    bit<1>   activated_exit_2;
    bit<8>   predict;
    bit<13>  swid;
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
    bit<5>   output_result = 0;

    bit<4>   activated = 0;
    bit<128> m1 = 0x55555555555555555555555555555555;
    bit<128> m2 = 0x33333333333333333333333333333333;
    bit<128> m4 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
    bit<128> m8 = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    bit<128> m16= 0x0000ffff0000ffff0000ffff0000ffff;
    bit<128> m32= 0x00000000ffffffff00000000ffffffff;
    bit<128> m64= 0x0000000000000000ffffffffffffffff;

    bit<16>  L4src = 0;
    bit<16>  L4dst = 0;

    // input: packet length, 5-tuple and tcp flag (bnn style)
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
    }

    action check_switch_id(switch_id_t swid){
        if (swid == 1){
            meta.is_ingress_border = (bit<1>)1;
        }
        if (swid == 4) {
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

    action early_exit_flag(bit<4>confidence) {
        bit<4> c_threshold = 7;
        if (confidence >= c_threshold){
            meta.early_exit_result = 1;
        }
        if (confidence < c_threshold) {
            meta.early_exit_result = 0;
        }
    }

    action predict() {
        // result-> ip filed (ip type of service tos / )
        if (meta.early_exit_1 < meta.early_exit_2) {
            meta.predict = 0;
        }
        else {
            meta.predict = 1;
        }
        hdr.ipv4.tos = meta.predict;
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

        if (meta.swid == 1) {
            if (hdr.ipv4.isValid()){
                 add_inference_header();

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
                     
                     predict();
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

                predict();
                hdr.inference.val = NextLayerInput;
             }

        }
        if (meta.swid == 1){
            standard_metadata.egress_spec = 2;
        }
        else{
            standard_metadata.egress_spec = 3;
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
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
            HashAlgorithm.csum16 );
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
