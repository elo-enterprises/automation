# Makefile.ansible-vault.mk:
#
# DESCRIPTION:
#   A makefile suitable for including in a parent makefile, smoothing
#   various lightweight crypto workflows using `ansible-vault`.
#		For more info on ansible-vault, see also:
#      https://docs.ansible.com/ansible/2.4/vault.html
#
# REQUIRES: (system tools)
#   * ansible-vault
#
# DEPENDS: (other makefiles)
#   * makefiles/Makefile.ssh.mk
#
# INTERFACE: (primary targets intended for export; see usage examples)
#   STANDARD TARGETS: (communicate with env-vars or make-vars)
#     * `vault-encrypt-path`: encrypt $path with standard key
#     * `vault-decrypt-path`: decrypt $path with standard key
#     * `vault-rekey-path`: rekey $path with given $oldkey, $newkey
#   PIPED TARGETS: (stdin->stdout)
#     * `vault-secret`: encrypt secret on stdin to stdout
#
# VARS: (toplevel overrides, suggested additions for usage as Makefile include)
#		ANSIBLE_ROOT = ${SRC_ROOT}/ansible
#		ANSIBLE_VAULT_PASSWORD_FILE := ${ANSIBLE_ROOT}/.vault_password
#
LIB_MAKEFILE = $(abspath $(lastword $(MAKEFILE_LIST)))
LIB_MAKEFILE := `python -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' ${LIB_MAKEFILE}`
LIB_ROOT := $(shell dirname ${LIB_MAKEFILE})

# include ${LIB_ROOT}/Makefile.base.mk

vault-base: assert-ANSIBLE_VAULT_PASSWORD_FILE assert-VAULT_CMD
	$(call _announce_target, $@)
	$(call _show_env, ANSIBLE)
	EDITOR=nano ansible-vault $$VAULT_CMD

# target `vault-encrypt-path`:
#
# usage example: encrypt a file at a certain path
#     $ path=/far/bar/baz make encrypt-path
vault-encrypt-path: assert-path
	$(call _announce_target, $@)
	VAULT_CMD="encrypt $(value path)" make vault-base

# --vault-password-file=$(value ANSIBLE_VAULT_PASSWORD_FILE)
encrypt-path: vault-encrypt-path
encrypt: encrypt-path

# target `vault-rekey`:
#
# usage example: rekey one file given $oldkey and $newkey
#     $ path=/far/bar/baz oldkey=old.key newkey=new.key make vault-rekey
vault-rekey: assert-oldkey assert-newkey assert-path
	$(call _announce_target, $@)
	ansible-vault encrypt \
		--new-vault-id=$$path \
		--new-vault-password-file=$$newkey \
		--vault-password-file=$$oldkey \
		$$path

# target `vault-decrypt-path`:
#
# example: decrypt a file at a certain path
#     $ path=/far/bar/baz make decrypt-path
decrypt: decrypt-path
decrypt-path: vault-decrypt-path
vault-decrypt-path: assert-path
		VAULT_CMD="decrypt $(value path)" make vault-base

# target `vault-secret`:
#
# usage examples: encode secret and put it on a file, or in the clipboard
#   $ echo hunter2 | make secret > password.txt
#   $ echo hunter2 | make secret | pbcopy
vault-secret: assert-ANSIBLE_VAULT_PASSWORD_FILE
	$(call _announce_target, $@)
	@VAULT_CMD="encrypt_string -" make vault-base
secret: vault-secret
vault-unsecret: assert-ANSIBLE_VAULT_PASSWORD_FILE
	$(call _announce_target, $@)
	@VAULT_CMD="decrypt -" make vault-base
unsecret: vault-unsecret

vault-edit: assert-ANSIBLE_VAULT_PASSWORD_FILE assert-path
		VAULT_CMD="edit $(value path)" make vault-base
