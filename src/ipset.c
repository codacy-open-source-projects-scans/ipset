/* Copyright 2000-2002 Joakim Axelsson (gozem@linux.nu)
 *                     Patrick Schaaf (bof@bof.de)
 * Copyright 2003-2010 Jozsef Kadlecsik (kadlec@netfilter.org)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */
#define _GNU_SOURCE
#include <assert.h>			/* assert */
#include <stdio.h>			/* fprintf */
#include <stdlib.h>			/* exit */
#include <string.h>			/* strcmp */

#include <config.h>
#include <libipset/ipset.h>		/* ipset library */
#include <libipset/xlate.h>		/* translate to nftables */
#include <libgen.h>

int
main(int argc, char *argv[])
{
	struct ipset *ipset;
	int ret;

	/* Load set types */
	ipset_load_types();

	/* Initialize ipset library */
	ipset = ipset_init();
	if (ipset == NULL) {
		fprintf(stderr, "Cannot initialize ipset, aborting.");
		exit(1);
	}

	if (!strcmp(basename(argv[0]), "ipset-translate")) {
		ret = ipset_xlate_argv(ipset, argc, argv);
	} else {
		ret = ipset_parse_argv(ipset, argc, argv);
	}

	ipset_fini(ipset);

	return ret;
}
