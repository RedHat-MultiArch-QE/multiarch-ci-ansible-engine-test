#!/bin/bash
#
# Attempts to clone down the test package and run it

# Ensure Ansible gets installed from task repo
sudo yum remove ansible -y &&
sudo yum-config-manager --save --setopt=epel.exclude=ansible* &&
sudo yum-config-manager --save --setopt=ansible.exclude=ansible*

cd "$(dirname ${BASH_SOURCE[0]})"
workdir=$(pwd)
rhpkg --verbose --user=jenkins clone tests/rhel-system-roles
cd rhel-system-roles
git checkout CoreOS-rhel-system-roles-Sanity-Upstream-testsuite-multiarch-ci-1_1-1
cd Sanity/Upstream-testsuite-multiarch-ci
output_dir="$workdir/artifacts/rhel-system-roles"
output_file="$output_dir/$(arch).txt"
mkdir -p $output_dir
sudo make &> $output_file run
grep "OVERALL RESULT" $output_file | grep "PASS"
