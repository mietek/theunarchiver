#import "CSFileHandle.h"

#include <sys/stat.h>



NSString *CSCannotOpenFileException=@"CSCannotOpenFileException";
NSString *CSFileErrorException=@"CSFileErrorException";




@implementation CSFileHandle

static inline void InitializeDeferredHandleIfNeeded(CSFileHandle *self)
{
	if(!self->fh && self->path) [self open];
}

static inline void LockForMultiAccessWithoutSeekingIfNeeded(CSFileHandle *self)
{
	if(self->multilock) [self->multilock lock];
}

static inline void LockForMultiAccessIfNeeded(CSFileHandle *self)
{
	if(self->multilock)
	{
		[self->multilock lock];
		fseeko(self->fh,self->pos,SEEK_SET);
	}
}

static inline void UnlockForMultiAccessIfNeeded(CSFileHandle *self)
{
	if(self->multilock)
	{
		self->pos=ftello(self->fh);
		[self->multilock unlock];
	}
}

+(CSFileHandle *)fileHandleForReadingAtPath:(NSString *)path
{ return [self fileHandleForPath:path modes:@"rb"]; }

+(CSFileHandle *)fileHandleForWritingAtPath:(NSString *)path
{ return [self fileHandleForPath:path modes:@"wb"]; }

+(CSFileHandle *)fileHandleForPath:(NSString *)path modes:(NSString *)modes
{
	if(!path) return nil;

	

	CSFileHandle *handle=[[[CSFileHandle alloc] initWithFilePointer:fileh closeOnDealloc:YES name:path] autorelease];
	if(handle) return handle;

	return nil;
}



-(id)initWithFilePointer:(FILE *)file closeOnDealloc:(BOOL)closeondealloc name:(NSString *)descname
{
	if((self=[super initWithName:descname]))
	{
		fh=file;
 		close=closeondealloc;
		path=nil;
		modes=nil;
		multilock=nil;
		parent=nil;
	}
	return self;
}

-(id)initWithPath:(NSString *)deferredpath modes:(NSString *)deferredmodes
{
	if((self=[super initWithName:path]))
	{
		fh=NULL;
 		close=YES;
		path=[deferredpath retain];
		modes=[deferredmodes retain];
		multilock=nil;
		parent=nil;
	}
	return self;
}

-(id)initAsCopyOf:(CSFileHandle *)other
{
	if((self=[super initAsCopyOf:other]))
	{
		fh=other->fh;
 		close=NO;
		parent=[other retain];

		path=[other->path retain];
		modes=[other->modes retain];

		if(!other->multilock) [other _setMultiMode];

		multilock=[other->multilock retain];
		[multilock lock];
		pos=other->pos;
		[multilock unlock];
	}
	return self;
}

-(void)dealloc
{
	if(fh && close) fclose(fh);

	[path release];
	[modes release];
	[multilock release];
	[parent release];

	[super dealloc];
}




-(void)open
{
	if(parent)
	{
		[parent open];
		fh=parent->fh;
		return;
	}

	if(!path) return;

	if(fh)
	{
		opencount++;
		return;
	}

	#if defined(__COCOTRON__) // Cocotron
	fh=_wfopen([path fileSystemRepresentationW],
	(const wchar_t *)[modes cStringUsingEncoding:NSUnicodeStringEncoding]);

	#elif defined(__MINGW32__) // GNUstep under mingw32 - sort of untested
	fh=_wfopen((const wchar_t *)[path fileSystemRepresentation],
	(const wchar_t *)[modes cStringUsingEncoding:NSUnicodeStringEncoding]);

	#else // Cocoa or GNUstep under Linux
	fh=fopen([path fileSystemRepresentation],[modes UTF8String]);
	#endif

	if(!fh) [NSException raise:CSCannotOpenFileException
	format:@"Error attempting to open file \"%@\" in mode \"%@\".",path,modes];
}

-(void)close
{
	if(fh && close)
	{
pos=ftello(fh);
		fclose(fh);
	}

	fh=NULL;
}

-(void)loseInterest
{
}




-(FILE *)filePointer { return fh; }

-(BOOL)isDeferred { return path?YES:NO; }

-(BOOL)isOpen { return fh?YES:NO; }




-(off_t)fileSize
{
	if(fh)
	{
		#if defined(__MINGW32__)
		struct _stati64 s;
		if(_fstati64(fileno(fh),&s)) [self _raiseError];
		#else
		struct stat s;
		if(fstat(fileno(fh),&s)) [self _raiseError];
		#endif

		return s.st_size;
	}
	else if(path)
	{
		#if defined(__COCOTRON__) // Cocotron
		struct _stati64 s;
		if(_wstat64([path fileSystemRepresentationW],&s)) [self _raiseError];
		#elif defined(__MINGW32__) // GNUstep under mingw32 - sort of untested
		struct _stati64 s;
		if(_wstat64((const wchar_t *)[path fileSystemRepresentation],&s)) [self _raiseError];
		#else
		struct stat s;
		if(lstat([path fileSystemRepresentation],&s)) [self _raiseError];
		#endif

		return s.st_size;
	}

	[self _raiseNotSupported:_cmd]; // TODO: Better error
}

-(off_t)offsetInFile
{
	if(!fh) return pos;
	else if(multilock) return pos;
	else return ftello(fh);
}

-(BOOL)atEndOfFile
{
	return [self offsetInFile]==[self fileSize];
/*
	InitializeDeferredHandleIfNeeded(self);
	if(multi) return pos==[self fileSize];
	else return feof(fh);*/ // feof() only returns true after trying to read past the end
}



-(void)seekToFileOffset:(off_t)offs
{
	InitializeDeferredHandleIfNeeded(self);
	LockForMultiAccessWithoutSeekingIfNeeded(self);

	//if(offs>[self fileSize]) [self _raiseEOF];
	if(fseeko(fh,offs,SEEK_SET)) [self _raiseError];

	UnlockForMultiAccessIfNeeded(self);
}

-(void)seekToEndOfFile
{
	InitializeDeferredHandleIfNeeded(self);
	LockForMultiAccessWithoutSeekingIfNeeded(self);

	if(fseeko(fh,0,SEEK_END)) [self _raiseError];

	UnlockForMultiAccessIfNeeded(self);
}

-(void)pushBackByte:(int)byte
{
	InitializeDeferredHandleIfNeeded(self);
	if(multilock) [self _raiseNotSupported:_cmd];

	if(ungetc(byte,fh)==EOF) [self _raiseError];
}

-(int)readAtMost:(int)num toBuffer:(void *)buffer
{
	if(num==0) return 0;

	InitializeDeferredHandleIfNeeded(self);
	LockForMultiAccessIfNeeded(self);

	int n=(int)fread(buffer,1,num,fh);
	if(n<=0 && !feof(fh)) [self _raiseError];

	UnlockForMultiAccessIfNeeded(self);

	return n;
}

-(void)writeBytes:(int)num fromBuffer:(const void *)buffer
{
	if(num==0) return;

	InitializeDeferredHandleIfNeeded(self);
	LockForMultiAccessIfNeeded(self);

	if(fwrite(buffer,1,num,fh)!=num) [self _raiseError];

	UnlockForMultiAccessIfNeeded(self);
}




-(void)_raiseError
{
	if(feof(fh)) [self _raiseEOF];
	else [[[[NSException alloc] initWithName:CSFileErrorException
	reason:[NSString stringWithFormat:@"Error while attempting to read file \"%@\": %s.",name,strerror(errno)]
	userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:errno] forKey:@"ErrNo"]] autorelease] raise];
}

-(void)_setMultiMode
{
	if(!multilock)
	{
		multilock=[NSLock new];
		pos=ftello(fh);
	}
}

@end
