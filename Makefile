VERSION=1.2.1

all:
	nroff -man snapdl.1 > snapdl.cat1

archive: all
	mkdir snapdl-${VERSION}
	cp Makefile snapdl.pl snapdl.1 snapdl-${VERSION}
	tar cfvz snapdl-${VERSION}.tar.gz snapdl-${VERSION}

clean:
	rm -rf snapdl.cat1 snapdl-*
