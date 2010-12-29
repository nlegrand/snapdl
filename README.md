Description
===========

snapdl downloads snapshots of OpenBSD -current. It helps you to find
where the snapshots are synchronised with the main mirror
[http://ftp.OpenBSD.org](http://ftp.OpenBSD.org) and which mirror is
the fastest. It may seem silly, but it's really quite useful to spot
fast mirrors and to skip those not synchronised.

It aims to stay bare with only perl core modules as dependencies: I
want to be able to fastly copy/past it on any machine and launch it.

Usage
=====

For the first time, launching the interactive mode is the most
straightforward way to use snapdl.

    $ git clone git://github.com/nlegrand/snapdl.git
    $ perl snapdl/snpadl.pl -i

Doc
===

    $ mandoc snapdl/snapdl.1 |less

New features in version 1.3.0-alpha
===================================

* Be non interactive by default.

* Prevent from redownloading the same snapshots.

* Set conf from <code>~/snapdl/snapdl.conf</code> or command line
  options.

* Report all tested mirror as synced, unsynced or timouted with
  <code>-r</code>.

* Report packages repository instead of sets with <code>-R</code>.

* You can change the http/ftp client as long as it has the same
  <code>-o</code> option as OpenBSD ftp(1). So it's now possible to
  use snapdl on Linux with curl : <code>snapdl -C curl</code>.

* The checksum at the end is now launched with Digest::SHA, so it
  works on Linux, Mac OS X or FreeBSD as on OpenBSD.

Bugs
====

If you find some don't hesitate to send me a mail at
[nlegrand@ethelred.fr](mailto:nlegrand@ethelred.fr), or comment on
github. It'll be even better with a patch or a git repository from
where I can pull :).

TODO
=====

* clean, debug and document.

* make interactive questions for version, comment, timeout.