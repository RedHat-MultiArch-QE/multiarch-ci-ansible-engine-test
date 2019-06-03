#!/bin/bash
#
# Attempts to clone down the test package and run it

# Save directory info
workdir="$(dirname ${BASH_SOURCE[0]})"
pushd $workdir

# Install dependencies
. /etc/os-release
OS_MAJOR_VERSION=$(echo $VERSION_ID | cut -d '.' -f 1)
if [ "$OS_MAJOR_VERSION" == "8" ]; then
    sudo yum install beakerlib python3-lxml koji brewkoji -y
fi

# Install beakerlib libraries
brew download-build --rpm beakerlib-libraries-0.4-1.module+el8+2902+97ffd857.noarch.rpm
ls *.rpm && sudo yum --nogpgcheck localinstall -y *.rpm

# Configure pulp repos
PULP_BASEURL=http://pulp.dist.prod.ext.phx2.redhat.com/content/dist
declare -A RHEL7_SOURCEDIRS=( ["x86_64"]="server" ["ppc64le"]="power-le" ["aarch64"]="arm-64" ["s390x"]="system-z" )
ANSIBLE_VER="2"
RHEL7_ANSIBLE_REPO=$PULP_BASEURL/rhel/${RHEL7_SOURCEDIRS[$(arch)]}/$OS_MAJOR_VERSION/$OS_MAJOR_VERSION$VARIANT/$(arch)/ansible/$ANSIBLE_VER/os
RHEL8_ANSIBLE_REPO=$PULP_BASEURL/layered/rhel8/$(arch)/ansible/$ANSIBLE_VER/os
case "$OS_MAJOR_VERSION" in
    "7") ANSIBLE_REPO=$RHEL7_ANSIBLE_REPO;;
    "8") ANSIBLE_REPO=$RHEL8_ANSIBLE_REPO;;
esac

# Install pulp ansible repo and gpg key
sudo yum-config-manager --add-repo  $ANSIBLE_REPO
sudo rpm --import https://www.redhat.com/security/fd431d51.txt

# Install test dependencies
sudo yum install -y ansible rhpkg yum-utils wget qemu-kvm genisoimage rhel-system-roles

# Clone test
rhpkg --verbose --user=jenkins clone tests/rhel-system-roles
cd rhel-system-roles
git checkout private-upstream_testsuite_refactor
cd Sanity/Upstream-testsuite

# Define output
output_dir="$workdir/artifacts/rhel-system-roles/results"
output_file="$output_dir/$(arch)-test-output.txt"
mkdir -p $output_dir

# Run the test
sudo make &> $output_file run

# Ensure Success and Restore Directory
grep "OVERALL RESULT" $output_file | grep "PASS" && popd
