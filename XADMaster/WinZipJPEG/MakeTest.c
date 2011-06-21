#include "ArithmeticDecoder.h"

#include <stdio.h>
#include <stdbool.h>
#include <ctype.h>

struct InputStream
{
	uint8_t *buffer;
	int pos,len;
};

static size_t ReadFunc(void *context,uint8_t *buffer,size_t count)
{
	struct InputStream *stream=context;
	*buffer=stream->buffer[stream->pos++];
	if(stream->pos>=stream->len) { fprintf(stderr,"Buffer overflow\n"); exit(1); }
	return 1;
}

int main(int argc,char **argv)
{
	if(argc<2)
	{
		fprintf(stderr,"Usage: MakeTest 1a2b3c4d5e6f... [state1 state2 ...]\n");
		exit(1);
	}


	printf(
	"\tstruct InputStream stream=\n"
	"\t{\n"
	"\t\t.buffer=(uint8_t[]){ ");

	char *inptr=argv[1];
	uint8_t buffer[65536];
	uint8_t *outptr=buffer;

	while(*inptr)
	{
		char c1=*inptr++;
		char c2=*inptr++;
		if(!c2) break;

		c1=tolower(c1);
		c2=tolower(c2);

		uint8_t val=0;

		if(c1>='0'&&c1<='9') val=(c1-'0')<<4;
		else if(c1>='a'&&c1<='f') val=(c1-'a'+10)<<4;

		if(c2>='0'&&c2<='9') val|=c2-'0';
		else if(c2>='a'&&c2<='f') val|=c2-'a'+10;

		*outptr++=val;

		printf("0x%02x,",val);
	}

	int numstates=argc-2;
	int states[numstates];
	for(int i=2;i<argc;i++) states[i-2]=atoi(argv[i]);

	printf(
	" },\n"
	"\t\t.pos=0\n"
	"\t};\n\n");

	struct InputStream stream=
	{
		.buffer=buffer,
		.pos=0,
		.len=outptr-buffer,
	};

	WinZipJPEGArithmeticDecoder decoder;
	InitializeWinZipJPEGArithmeticDecoder(&decoder,ReadFunc,&stream);

	printf(
	"struct KnownState knownstates[]=\n"
	"{\n"
	"//\t i,s,yn,mps,  lr,   lrm,         x,      dx,   k,   lp,    lx\n"
	"\t{ 0,-1,-1,-1,0x%04x,0x%04x,0x%08x,-1,-1,-1,-1 },\n",
	decoder.lr,decoder.lrm,decoder.x);
	
	int i=0;
	while(stream.pos<stream.len-1)
	{
		int state=0;
		if(numstates) state=states[i%numstates];
		int bit=NextBitFromWinZipJPEGArithmeticDecoder(&decoder,state);

		printf(
		"\t{ %d,%d,%d,%d,0x%04x,0x%04x,0x%08x,0x%06x,0x%02x,0x%03x,0x%04x },\n",
		++i,decoder.s,decoder.yn,decoder.mps,decoder.lr,decoder.lrm,decoder.x,decoder.dx,decoder.k,decoder.lp,(uint16_t)decoder.lx);
	}

	printf("};\n");

	return 0;
}

//	{ 0,-1,-1,0x1001,0x1001,0x0000efd9,-1,-1,-1,-1 }, // This line seems to be wrong in the original patent.
//	{ 1,1,0,0x1401,0x5001,0x00006fe5,0x007ff4,0x01,0x400,0x14c8 },

