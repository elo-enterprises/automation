#!/usr/bin/make -f
# Makefile.base.mk:
#
# DESCRIPTION:
#   A makefile suitable for including in a parent makefile, smoothing various
#   really basic makefile workflows and usage patterns.  This file adds some
#   data/support functionality for autogenerating `make help` from target
#   definitions, coloring user output, primitives for structured arguments
#  (doing assertions on required environment variables), and more.
#
# REQUIRES: (system tools)
#   * python (only stdlib)
#
# DEPENDS: (other makefiles)
#   * nothing, this is the base include for everything else.
#
# EXPORTS: (data available to other makefiles)
#   * MY_MAKEFLAGS: like builtin ${MAKEFLAGS}, but includes --makefile args
#
## INTERFACE: (primary targets intended for export; see usage examples)
#   STANDARD TARGETS: (communicate with env-vars or make-vars)
#     * `require-%`:for usage as pre-requisite target, with
#				the provided parameter.  this guard is used to assert
#       an executable exists in $PATH before entering another
#       target
#     * `assert-%`: for usage as pre-requisite target, with
#				the provided parameter.  this guard is used to assert
#       an environment variable before entering another target
#     * `help`: autogenerated help output for targets (and included targets)
#   PIPED TARGETS: (stdin->stdout)
#     * None.  But common targets from other areas could be
#       promoted here eventually if they feel like "core"
#   MAKE-FUNCTIONS:
#     * `_show_env`: dump a subset of env-vars for easy debugging
#     * `_INFO`, `_DEBUG`,`_WARN`: standard loggers, colored
#

SHELL := bash
MAKEFLAGS += --warn-undefined-variables --no-print-directory
.SHELLFLAGS := -euo pipefail -c

# ${MAKEFLAGS} is standard, but does not include --file arguments, see
# https://www.gnu.org/software/make/manual/html_node/Options_002fRecursion.html
# this is a constant annoyance whenever make targets want to invoke other make
# targets with the same environment.  an example value here is something like
# `-f Makefile.base.mk -f Makefile.ansible.mk`.  this macro is obnoxious, and
# it makes a strong assumption that only one make-target is given in the main
# CLI, but it's struggling to succinct and portable
MY_MAKEFLAGS:=$(shell \
	ps -p $${PPID} -o command | tail -1 \
	| xargs -n 1 | tail -n +2  | sed '$$d' | xargs)

define _INFO
	printf "$(COLOR_YELLOW)(`hostname`) [$@]:$(NO_COLOR) INFO $1\n" 1>&2;
endef
define _WARN
	printf "$(COLOR_RED)(`hostname`) [$@]:$(NO_COLOR) WARN $1\n" 1>&2;
endef
define _DEBUG
	printf "$(COLOR_RED)(`hostname`) [$@]:$(NO_COLOR) DEBUG $1\n" 1>&2;
endef

# BEGIN: Parametric makefile-target `assert-%` and `require-%`,
# for use as prerequisites for other targets.  These are used as decorators or
# implicit guards for other targets, where `assert-%` fails if the named
# environment variable is not present, and where `require-%` fails if the named
# external utility is not present.
#
# Example usage:
#
#		grep-json: assert-PATH assert-KEY require-jq
#   	cat $$PATH | jq .$$KEY
#
define _announce_assert
	export tmp=`echo '${1}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$$//'` \
	; printf "$(COLOR_YELLOW)(`hostname`)$(NO_COLOR) [$$tmp]:$(NO_COLOR) (=$2)\n" 1>&2;
endef
define _assert_var
	@if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* is not set" 1>&2; \
		exit 1; \
	fi
endef
define _assertnot_var
	@if [ "${${*}}" != "" ]; then \
		echo "Environment variable $* is set, and shouldn't be!" 1>&2; \
		exit 1; \
	fi
endef
# BEGIN: Helpers for console messaging

# Example usage: (announcing the name of the current target on entry):
#
#    my-target:
#    	  $(call _announce_target, $@)
define _announce_target
	@printf "$(COLOR_GREEN)(`hostname`)$(NO_COLOR)$(COLOR_CYAN) *$(abspath $(firstword $(MAKEFILE_LIST)))*$(NO_COLOR)\n   $(COLOR_LBLUE)[target]:$(NO_COLOR) $@\n" 1>&2
endef

# Example usage: (announcing the name of a section, with dividers):
#
#    my-target:
#    	  $(call _announce_section, "FooSection")
#
# Or equivalently:
#   my-target: announce-section-FooSection
define _announce_section
	@printf "\n\n------------$(NO_COLOR)$(COLOR_YELLOW)`echo ${1} | awk '{ print toupper($$0) }'`$(NO_COLOR)------------\n\n"  1>&2
endef
announce-section-%:
	$(call _announce_section, $*)

	# Example usage: (announcing the name of a stage where targets may have several):
	#
	#    my-target:
	#    	  $(call _announce_section, "stage one")
	#       ...
	#    	  $(call _announce_section, "stage two")
define _stage
	@printf "$(COLOR_YELLOW)(`hostname`) [stage]:$(NO_COLOR) ${1}\n " 1>&2;
endef

define _fail
	@INDENTION="  "; \
	printf "$(COLOR_RED)(`hostname`) [FAIL]:$(NO_COLOR)\n$${INDENTION}${1}\n" 1>&2;
	exit 1
endef
fail:
	$(call _fail, $${MSG})

# `_show_env`: A make function for showing the contents of all environment
# variables.  This information goes to stderr so it can be safely used in
# make-targets that do stdin/stdout piping.  The argument to this function is
# passed as an argument for `grep`, thus filtering the output of the `env`.
#
#  example usage: (from a make-target, show only .*ANSIBLE.* vars in env)
#
#     target_name:
#      $(call _show_env, ANSIBLE)
#
#  example usage: (from a make-target, show .*ANSIBLE.* or .*VIRTUALENV.* vars)
#
#     target_name:
#				$(call _show_env, "\(ANSIBLE\|VIRTUAL\)")
#
define _show_env
	@printf "$(COLOR_YELLOW)(`hostname`) [<env filter=$1>]:$(NO_COLOR)\n" 1>&2;
	@env | grep $1 | sed 's/^/  /' 1>&2 || true
	@printf "$(COLOR_YELLOW)(`hostname`) [</env>]:$(NO_COLOR)\n"
endef

assert-%:
	$(call _announce_assert, $@, ${${*}})
	$(call _assert_var, $*)
assertnot-%:
	$(call _assertnot_var, $*)

# Example usage: (for existing make-target, declare command in $PATH as prereq)
#
#    my-target: requires-foo_cmd
#      foo_cmd arg1,arg2
#
require-%: ## bonk bonk
	@which $* > /dev/null

# BEGIN: Target for `make help` and friends.
#
# This causes `make help` to publish all the make-target names to stdout.
# This is a hack since make isn't exactly built to support reflection,
# but all the complexity here is inspection, string parsing, and still
# (always?) works correctly even in case of usage of macros and make-includes.
#
# Example usage: (from command line)
#
#   $ make help
#   [target]: help
#   ansible-provision
#	  ansible-provision-inventory-playbook
#   ..
#   ..
.PHONY: no_targets__ list
no_targets__:
_help-helper:
	@sh -c "\
	$(MAKE) -p no_targets__ | \
	awk -F':' '/^[a-zA-Z0-9][^\$$#\/\\t=]*:([^=]|$$)/ {split(\$$1,A,/ /);\
	for(i in A)print A[i]}' | grep -v '__\$$' | grep -v '\[' | sort"
help:
	@make _help-helper | make _help-parser

_help-parser: private SHELL=python2
_help-parser: private .SHELLFLAGS = -c
.SILENT:_help-parser
_help-parser:
	from __future__ import print_function; \
	import os, re, sys, functools; \
	from collections import OrderedDict; \
	merge = lambda x, **y: { k:v for k,v in x.items()+y.items() }; \
	tcom = '^{}:.*\n(.*[@]?#.*\n)+'; \
	_docs = lambda h: h['file'] and re.search( \
			tcom.format(h['target']), \
			open(h['abs_path'], 'r').read(), \
			re.MULTILINE); \
	inp = sys.stdin.read(); \
	lines = inp.split('\n'); \
	ignored = 'Makefile list fail i in not if else for'.split(); \
	fstarts = 'assert range('.split(); \
	targets = [ x.strip() for i, x in enumerate(lines) if x.strip() not in ignored and not any([x.startswith(y) for y in fstarts]) ]; \
	inp2 = os.popen('make -p no_targets__'); \
	inp2_lines = inp2.readlines() ; \
	hints = [ [ line.strip(), '\n'.join(inp2_lines[i:i+6]) ] for i, line in enumerate(inp2_lines) if any([line.strip().startswith(t+':') for t in targets]) ]; \
	hints = [ [ t, block[block.find('recipe to execute (from '):].split('\n')[0] ] for t, block in hints]; \
	hints = [ [ t, block[block.find('(from ')+7:block.rfind(')')+2]] for t, block in hints ]; \
	hints = [ [ t, block.split(', ')[0][:-1] +' '+ block.split(', ')[-1][:-2]] for t, block in hints ]; \
	hints = [ dict( \
		target=t.split(':')[0], \
		args=t.split(':')[-1].split(), \
		file=block.strip().split() and block.split()[0], \
		line=block.strip().split() and block.split(' line ')[-1]) for t, block in hints ]; \
		print(hints); print('----------'); \
	hints = [ merge(h, \
		args=[_.strip() for _ in h['args'] if _.strip()], \
		abs_path=h['file'], \
		file=(h['file'] and h['file'].replace(os.getcwd(), '.')) or None,) \
		for h in hints ]; \
	hints = [ merge(h, \
		source=':'.join([h['file'], h['line']]) if (h['file'] and h['line']) else '?',) \
		for h in hints ]; \
	hints = [ merge(h, \
		prereqs=[x for x in h['args'] if not x.startswith('assert-')],) \
		for h in hints ]; \
	hints = [ merge(h, \
		args=functools.reduce(lambda x,y: x+y, [_.split() for _ in h['args']],[]),) \
		for h in hints ]; \
	hints = [ merge(h, docs=_docs(h),) for h in hints ]; \
	hints = [ merge(h, docs=h['docs'].group(0).split('\n') if h['docs'] else [],) for h in hints ]; \
	hints = [ merge(h, docs=[x.lstrip().replace("@#","##").replace('##','#') for x in h['docs']][1:],) for h in hints ]; \
	hints = [ merge(h, args=[x[len('assert-'):] for x in h['args'] if x.startswith('assert-')],) for h in hints ]; \
	print(hints); print('----------'); \
	targets = sorted(hints, key=lambda _: _['target']); \
	targets = OrderedDict([[_['target'], _] for _ in targets]); \
	src_files = set([x['file'] for x in hints]); \
	sources = [ [f, [h for h in hints if h['file']==f]] for f in src_files if f ]; \
	sources = sorted(sources, key=lambda _: _[0]); \
	sources = OrderedDict(sources); \
	thdr = '[$(COLOR_GREEN){target}$(NO_COLOR)] ($(COLOR_CYAN){source}$(NO_COLOR))\n'; \
	shdr = '\n$(COLOR_YELLOW)--- TARGETS BY SOURCE---$(NO_COLOR)\n\n'; \
	msg_t = '[$(COLOR_BLUE){file}$(NO_COLOR)] ($(COLOR_CYAN){count} targets$(NO_COLOR))\n{summary}'; \
	print(shdr + '\n'.join([msg_t.format( \
		file=file, count=len(targets), \
		summary='\n'.join(['    '+thdr.format(**t) for t in tlist]) + '\n',) \
		for file, tlist in sources.items()])); \
	msg_t = thdr; \
	msg_t+= '{args}'; \
	msg_t+= '{prereqs}'; \
	msg_t+= '$(COLOR_DIM){docs}$(COLOR_RDIM)'; \
	print('\n$(COLOR_YELLOW)--- ALL TARGETS ---$(NO_COLOR)\n\n  ' + \
		'\n  '.join(\
			[	msg_t.format( \
					target = h['target'], \
					source = h['source'], \
					docs = ('    '+'\n    '.join(h['docs'])) if h['docs'] else '', \
					args = '    $(COLOR_MAGENTA)args:${NO_COLOR} {}\n'.format(h['args']) if h['args'] else '', \
					prereqs='    $(COLOR_RED)prereqs:$(NO_COLOR) {}\n'.format(h['prereqs']) if h['prereqs'] else '', \
				) for _, h in targets.items() \
			]),\
	)

# BEGIN: Color settings
#
# See also references at
#   * https://gist.github.com/vratiu/9780109
#   * https://godoc.org/github.com/whitedevops/colors
#
NO_COLOR:=\033[0m
COLOR_GREEN=\033[92m
COLOR_DIM=\033[2m
COLOR_RDIM=\033[22m
COLOR_OK=${COLOR_GREEN}
COLOR_RED=\033[91m
COLOR_CYAN=\033[96m
COLOR_LBLUE=\033[94m
COLOR_MAGENTA=\033[35m
COLOR_BLUE=${COLOR_LBLUE}
COLOR_PURPLE=\[\033[0;35m\]
ERROR_COLOR=${COLOR_RED}
WARN_COLOR:=\033[93m
	WARN_COLOR:=\033[93m
COLOR_YELLOW=${WARN_COLOR}
OK_STRING=$(COLOR_GREEN)[OK]$(NO_COLOR)
ERROR_STRING=$(ERROR_COLOR)[ERROR]$(NO_COLOR)
WARN_STRING=$(WARN_COLOR)[WARNING]$(NO_COLOR)
