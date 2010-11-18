Description
===========

snapdl downloads snapshots of OpenBSD -current. It helps you to find
where the snapshots are synchronised with the main mirror
[http://ftp.OpenBSD.org](http://ftp.OpenBSD.org) and which mirror is
the fastest. It may seem silly, but it's really quite useful to spot
fast mirrors and to skip those not synchronised.

Installation
============

snapdl is packaged in the OpenBSD ports, so you just have to type:

<code>
$ sudo pkg_add -i snapdl
</code>

to install it on a properly configured OpenBSD system. Read the
[doc](http://www.openbsd.org/faq/faq15.html#Easy) for more
information.

Or you can use it by cloning it from Github:

<code>
$ git clone git://github.com/nlegrand/snapdl.git
</code>

Usage
=====

Type:

<code>
$ snapdl
</code>

or

<code>
$ perl snapdl/snpadl.pl
</code>

if you cloned it from Github and answer questions.

Bugs
====

Oups, I wrote it mainly for OpenBSD, it rely deeply on *BSD ftp(1) and
and won't work for Linux. It makes a final check with OpenBSD cksum(1)
wich work the same on NetBSD, but not on Mac OS X or FreeBSD. So the
checksum will fail on those two systems.

TODO
=====

* write a module to tell which mirror package directory is
  synchronised with main mirror.

* stop the chatty interactive mess and write something that can be
  cronable.

* make snapdl check if a preceding download is the same as the one
  available right now to prevent it from downloading the same thing
  again.

* make something than run well on Mac OS X, FreeBSD and Linux at
  least.