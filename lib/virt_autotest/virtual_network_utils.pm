# SUSE's openQA tests
#
# Copyright 2019-2023 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: virtual_network_utils:
#          This file provides fundamental utilities for virtual network.
# Maintainer: Leon Guo <xguo@suse.com>, qe-virt@suse.de

package virt_autotest::virtual_network_utils;

use base Exporter;
use Exporter;

use utils;
use strict;
use warnings;
use File::Basename;
use testapi;
use Data::Dumper;
use XML::Writer;
use IO::File;
use utils 'script_retry';
use upload_system_log 'upload_supportconfig_log';
use version_utils qw(is_sle is_alp);
use virt_autotest::utils;

our @EXPORT
  = qw(download_network_cfg prepare_network restore_standalone destroy_standalone
  restore_guests restore_network destroy_vir_network restore_libvirt_default pload_debug_log
  check_guest_status check_guest_module check_guest_ip save_guest_ip test_network_interface hosts_backup
  hosts_restore get_free_mem get_active_pool_and_available_space clean_all_virt_networks setup_vm_simple_dns_with_ip
  get_guest_ip_from_vnet_with_mac update_simple_dns_for_all_vm validate_guest_status);

sub check_guest_ip {
    my ($guest, %args) = @_;
    my $net = $args{net} // "br123";

    # get some debug info about vm host network
    script_run 'ip neigh';
    script_run 'ip a';

    # ensure guest is still alive
    if (script_output("virsh domstate $guest") eq "running") {
        my $mac_guest = script_output("virsh domiflist $guest | grep $net | grep -oE \"[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}\"");
        my $gi_guest = '';
        if (is_alp) {
            $gi_guest = get_guest_ip_from_vnet_with_mac($mac_guest, $net);
        } else {
            my $syslog_cmd = "journalctl --no-pager | grep DHCPACK";
            script_retry "$syslog_cmd | grep $mac_guest | grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"", delay => 90, retry => 9, timeout => 90;
            $gi_guest = script_output("$syslog_cmd | grep $mac_guest | tail -1 | grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
        }
        setup_vm_simple_dns_with_ip($guest, $gi_guest);
        script_retry("nmap $guest -PN -p ssh | grep open", delay => 30, retry => 6, timeout => 60) if ($guest =~ m/sles-11/i);
        die "Ping $guest failed !" if (script_retry("ping -c5 $guest", delay => 30, retry => 6, timeout => 60) ne 0);
    }
}

sub get_guest_ip_from_vnet_with_mac {
    my ($mac, $net) = @_;

    my $cmd = "virsh net-dhcp-leases $net | sed  '1,2d' | grep '$mac'";
    script_retry($cmd, delay => 3, retry => 20);
    $cmd .= " | gawk '{print \$5 }' | sed -r 's/\\\/[0-9]+//'";
    return script_output($cmd);
}

sub check_guest_module {
    my ($guest, %args) = @_;
    my $module = $args{module};
    my $net = $args{net} // "br123";
    if (($guest =~ m/sles-?11/i) && ($module eq "acpiphp")) {
        save_guest_ip("$guest", name => $net);
        my $status = script_run("ssh root\@$guest \"lsmod | grep $module\"");
        if ($status != 0) {
            script_run("ssh root\@$guest modprobe $module", 60);
            record_info('bsc#1167828 - need to load acpiphp kernel module to sles11sp4 guest otherwise network interface hotplugging does not work');
        }
    }
}

sub save_guest_ip {
    my ($guest, %args) = @_;
    my $name = $args{name};

    # If we don't know guest's address or the address is wrong so the guest is not responding to ICMP
    if (script_run("grep $guest /etc/hosts") != 0 || script_retry("ping -c3 $guest", delay => 6, retry => 30, die => 0) != 0) {
        assert_script_run "virsh domiflist $guest";
        my $mac_guest = script_output("virsh domiflist $guest | grep $name | grep -oE \"[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}\"");
        my $gi_guest = '';
        if (is_alp) {
            $gi_guest = get_guest_ip_from_vnet_with_mac($mac_guest, $name);
        } else {
            my $syslog_cmd = is_sle('=11-sp4') ? 'grep DHCPACK /var/log/messages' : 'journalctl --no-pager | grep DHCPACK';
            script_retry "$syslog_cmd | grep $mac_guest | grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"", delay => 90, retry => 9, timeout => 90;
            $gi_guest = script_output("$syslog_cmd | grep $mac_guest | tail -1 | grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
        }
        setup_vm_simple_dns_with_ip($guest, $gi_guest);
        script_retry("nmap $guest -PN -p ssh | grep open", delay => 30, retry => 6, timeout => 60) if ($guest =~ m/sles-11/i);
        die "Ping $guest failed !" if (script_retry("ping -c5 $guest", delay => 30, retry => 6, timeout => 60) ne 0);
    }
}

sub test_network_interface {
    my ($guest, %args) = @_;
    my $net = $args{net};
    my $mac = $args{mac};
    my $gate = $args{gate};
    my $isolated = $args{isolated} // 0;
    my $routed = $args{routed} // 0;
    my $target = $args{target} // script_output("dig +short google.com");
    # Expect $target is an IP address
    if ($target !~ /^[\d\.]+/) {
        record_info("Incorrect remote target to test your network connection", $target, result => 'fail');
        $target = script_output("dig +short libvirt.org");
        $target =~ /^[\d\.]+/ ? record_info("One more try succeed!") : die "Unable to test network connections!";
    }
    else {
        $target =~ s/\n.*//gm;
    }

    record_info("Network test", "testing $mac");
    check_guest_ip("$guest", net => $net) if ((is_sle('>15') || is_alp) && ($isolated == 1) && get_var('VIRT_AUTOTEST'));

    save_guest_ip("$guest", name => $net);

    # Configure the network interface to use DHCP configuration
    #flag SRIOV test as it need not restart network service
    my $is_sriov_test = "false";
    $is_sriov_test = "true" if caller 0 eq 'sriov_network_card_pci_passthrough';
    script_retry("nmap $guest -PN -p ssh | grep open", delay => 30, retry => 6, timeout => 180);
    my $nic = script_output "ssh root\@$guest \"grep '$mac' /sys/class/net/*/address | cut -d'/' -f5 | head -n1\"";
    die "$mac not found in guest $guest" unless $nic;
    if ((get_var('TEST', '') =~ m/qam-(kvm|xen)-install-and-features-test/ || $is_sriov_test eq "true") and !is_sle('16+')) {
        assert_script_run("ssh root\@$guest \"echo BOOTPROTO=\\'dhcp\\' > /etc/sysconfig/network/ifcfg-$nic\"");

        # Restart the network - the SSH connection may drop here, so no return code is checked.
        if ($is_sriov_test ne "true") {
            script_run("ssh root\@$guest systemctl restart network", 300);
        }
        # Exit the SSH master socket if open
        script_run("ssh -O exit root\@$guest");
        # Wait until guest's primary interface is back up
        script_retry("ping -c3 $guest", delay => 6, retry => 30);
        # Activate guest's secondary (tested) interface
        script_retry("ssh root\@$guest ifup $nic", delay => 10, retry => 20, timeout => 120);
    }

    # See obtained IP addresses
    script_run("virsh net-dhcp-leases $net") unless $is_sriov_test eq "true";

    # Show the IP address of secondary (tested) interface
    assert_script_run("ssh root\@$guest ip -o -4 addr list $nic | awk \"{print \\\$4}\" | cut -d/ -f1 | head -n1");
    my $addr = "";
    my $test_timeout = ($net eq 'vnet_host_bridge') ? 360 : 90;
    my $start_time = time();
    while (time() - $start_time <= $test_timeout) {
        $addr = script_output("ssh root\@$guest ip -o -4 addr list $nic | awk \"{print \\\$4}\" | cut -d/ -f1 | head -n1", proceed_on_failure => 1);
        last if ($addr ne "");
        sleep 30;
    }
    if ($addr eq "") {
        assert_script_run "ssh root\@$guest 'ip a'";
        die "No IP found for $nic in $guest";
    }

    # Route our test via the tested interface
    script_run "ssh root\@$addr '[ `ip r | grep $target | wc -l` -gt 0 ] && ip r del $target'";
    assert_script_run("ssh root\@$addr ip r a $target via $gate dev $nic");

    if ($isolated == 0) {
        assert_script_run("ssh root\@$addr 'ping -I $nic -c 3 $target' || true", 60);
    } else {
        assert_script_run("! ssh root\@$addr 'ping -I $nic -c 3 $target' || true", 60);
    }
    save_screenshot;

    # Restore the network interface to the default for the Xen guests
    if ($is_sriov_test ne "true") {
        if (is_xen_host()) {
            assert_script_run("ssh root\@$guest 'cd /etc/sysconfig/network/; cp ifcfg-eth0 ifcfg-$nic'");
        }
    }
}

sub download_network_cfg {
    #Download required libvird virtual network configuration file
    my $vnet_cfg_name = shift;
    my $wait_script = "180";
    my $vnet_cfg_url = data_url("virt_autotest/$vnet_cfg_name");
    my $download_cfg_script = "curl -s -o ~/$vnet_cfg_name $vnet_cfg_url";
    script_output($download_cfg_script, $wait_script, type_command => 0, proceed_on_failure => 0);
}

sub prepare_network {
    #Confirm the host bridge configuration file
    my ($virt_host_bridge, $based_guest_dir) = @_;
    my $config_path = "/etc/sysconfig/network/ifcfg-$virt_host_bridge";

    if (script_run("[[ -f $config_path ]]") != 0) {
        assert_script_run("ip link add name $virt_host_bridge type bridge");
        assert_script_run("ip link set dev $virt_host_bridge up");
        my $wait_script = "180";
        my $bash_script_name = "vm_host_bridge_init.sh";
        my $bash_script_url = data_url("virt_autotest/$bash_script_name");
        my $download_bash_script = "curl -s -o ~/$bash_script_name $bash_script_url";
        script_output($download_bash_script, $wait_script, type_command => 0, proceed_on_failure => 0);
        my $execute_bash_script = "chmod +x ~/$bash_script_name && ~/$bash_script_name $virt_host_bridge";
        script_output($execute_bash_script, $wait_script, type_command => 0, proceed_on_failure => 0);
        #Create required host bridge interface br0 on sles hosts for libvirt virtual network testing
        #Need to reset up environment, included recreate br123 bridege interface for virt_auto test
        restore_standalone();
        #Need to recreate all guests system depned on the above prepare network operation on vm host
        recreate_guests($based_guest_dir);
    }
}

sub restore_network {
    my ($virt_host_bridge, $based_guest_dir) = @_;
    my $network_mark = "/etc/sysconfig/network/ifcfg-$virt_host_bridge.new";

    if (script_run("[[ -f $network_mark ]]") == 0) {
        #Restore all defined guest system before restore Network setting on vm host
        restore_guests();
        assert_script_run("rm -rf /etc/sysconfig/network/ifcfg-$virt_host_bridge*", 60);
        my $wait_script = "180";
        my $bash_script_name = "vm_host_bridge_final.sh";
        my $bash_script_url = data_url("virt_autotest/$bash_script_name");
        my $download_bash_script = "curl -s -o ~/$bash_script_name $bash_script_url";
        script_output($download_bash_script, $wait_script, type_command => 0, proceed_on_failure => 0);
        my $execute_bash_script = "chmod +x ~/$bash_script_name && ~/$bash_script_name $virt_host_bridge";
        script_output($execute_bash_script, $wait_script, type_command => 0, proceed_on_failure => 0);
        #After destroyed host bridge interface br0 on sles vm hosts
        #Need to reset environment again depend on the following virt_auto tests required
        restore_standalone();
        #Recreate all defined guest depend on the above restore network operation on vm host
        #And Keep all guest as running status for the following virtual network tests
        recreate_guests($based_guest_dir);
    }
}

sub restore_standalone {
    #File standalone was installed from qa_test_virtualization package
    my $standalone_path = "/usr/share/qa/qa_test_virtualization/shared/standalone";
    assert_script_run("source $standalone_path", 60) if (script_run("[[ -f $standalone_path ]]") == 0);
}

sub hosts_backup {
    #During virtual network testing, there will be modified file /etc/hosts depend on
    #testing required, to keep connection both on vm host and guests system via ssh
    #So, would be better to backup file /etc/hosts before virtual network testing
    my $hosts_file = "/etc/hosts";
    my $hosts_backup = "/etc/hosts.orig";
    assert_script_run("cp $hosts_file $hosts_backup", 60) if (script_run("[[ -f $hosts_file ]]") == 0);
}

sub hosts_restore {
    #After finished all virtual network testing, need to restore file /etc/hosts from backup
    #for the following virt_auto testing
    my $hosts_restore = "/etc/hosts.orig";
    my $hosts_file = "/etc/hosts";
    assert_script_run("cp $hosts_restore $hosts_file", 60) if (script_run("[[ -f $hosts_restore ]]") == 0);
}

sub destroy_standalone {
    #File cleanup was installed from qa_test_virtualization package
    my $cleanup_path = "/usr/share/qa/qa_test_virtualization/cleanup";
    assert_script_run("source $cleanup_path", 60) if (script_run("[[ -f $cleanup_path ]]") == 0);
}

sub restore_guests {
    return if get_var('INCIDENT_ID');    # QAM does not recreate guests every time
    my $get_vm_hostnames = "virsh list --all | grep -e sles -e opensuse -e alp -i | awk \'{print \$2}\'";
    my $vm_hostnames = script_output($get_vm_hostnames, 30, type_command => 0, proceed_on_failure => 0);
    my @vm_hostnames_array = split(/\n+/, $vm_hostnames);
    foreach (@vm_hostnames_array)
    {
        script_run("virsh destroy $_");
        script_run("virsh undefine $_ || virsh undefine $_ --keep-nvram");
        script_run("virsh define /tmp/$_.xml");
    }
}

sub destroy_vir_network {
    #Get the created virtual network name
    my $get_vnet_name = "virsh net-list --all| grep vnet | head -1 | awk \'{print \$1}\'";
    my $vnet_name = script_output($get_vnet_name, 30, type_command => 0, proceed_on_failure => 0);
    my @vnet_name_array = split(/\n+/, $vnet_name);
    foreach (@vnet_name_array) { script_run("virsh net-destroy $_"); }
}

sub restore_libvirt_default {
    my $default_path = "/root/libvirt_default.xml";
    if (script_run("[[ -f $default_path ]]") == 0) {
        assert_script_run("virsh net-define $default_path", 60);
        assert_script_run("rm -rf $default_path");
    }
}

sub upload_debug_log {
    script_run("dmesg > /tmp/dmesg.log");
    upload_virt_logs("/tmp/dmesg.log /var/log/libvirt /var/log/messages", "libvirt-virtual-network-debug-logs");
    if (get_var("XEN") || check_var("HOST_HYPERVISOR", "xen")) {
        script_run("xl dmesg > /tmp/xl-dmesg.log");
        upload_virt_logs("/tmp/dmesg.log /var/log/libvirt /var/log/messages /var/log/xen /var/lib/xen/dump /tmp/xl-dmesg.log", "libvirt-virtual-network-debug-logs");
    }
    upload_system_log::upload_supportconfig_log();
    script_run("rm -rf scc_* nts_*");
}

sub check_guest_status {
    my $wait_script = "30";
    my $vm_types = "sles|alp";
    my $get_vm_hostnames = "virsh list  --all | grep -E \"$vm_types\" -i | awk \'{print \$2}\'";
    my $vm_hostnames = script_output($get_vm_hostnames, $wait_script, type_command => 0, proceed_on_failure => 0);
    my @vm_hostnames_array = split(/\n+/, $vm_hostnames);
    foreach (@vm_hostnames_array) {
        if (script_run("virsh list --all | grep $_ | grep shut") != 0) { script_run "virsh destroy $_", 90;
            #Wait for forceful shutdown of active guests
            sleep 20;
        }
    }

}

sub get_free_mem {
    if (is_xen_host) {
        # ensure the free memory size on xen host
        my $mem = script_output q@xl info | grep ^free_memory | awk '{print $3}'@;
        $mem = int($mem / 1024);
        return $mem;
    }
}

sub get_active_pool_and_available_space {
    # get some debug info about hard disk topology
    script_run 'df -h';
    script_run 'df -h /var/lib/libvirt/images/';
    script_run 'lsblk -f';
    # get some debug info about storage pool
    script_run 'virsh pool-list --details';
    # ensure the available disk space size for active pool
    my $active_pool = '';
    if (is_alp) {
        $active_pool = script_output("virsh pool-list | grep -ivE \"nvram|boot\" | grep active | awk '{print \$1}'");
    } else {
        $active_pool = script_output("virsh pool-list --persistent | grep -iv nvram | grep active | awk '{print \$1}'");
    }
    my $available_size = script_output("virsh pool-info $active_pool | grep ^Available | awk '{print \$2}'");
    my $pool_unit = script_output("virsh pool-info $active_pool | grep ^Available | awk '{print \$3}'");
    # default available pool unit as GiB
    $available_size = ($pool_unit eq "TiB") ? int($available_size * 1024) : int($available_size);
    return ($active_pool, $available_size);
}

sub clean_all_virt_networks {
    my $_virt_networks = script_output("virsh net-list --name --all", 30, type_command => 0, proceed_on_failure => 0);

    foreach my $vnet (split(/\n+/, $_virt_networks)) {
        my $_br = script_output(q@virsh net-dumpxml @ . $vnet . q@|grep -o "bridge name=[^\s]*" | sed  's#bridge name=##'@, type_command => 0, proceed_on_failure => 0);
        script_run("virsh net-destroy $vnet");
        script_run("virsh net-undefine $vnet");
        assert_script_run("if ip a|grep $_br;then ip link del $_br;fi");
        save_screenshot;
    }

    die "Virtual networks are not fully cleaned!" if (script_output("virsh net-list --name --all"));
    record_info("All existing virtual networks: \n$_virt_networks \nhave been destroy and undefined.", script_output("ip a; ip route show all"));
}

sub setup_vm_simple_dns_with_ip {
    my ($_vm, $_ip) = @_;

    my $_dns_file = '/etc/hosts';

    # Workaround for directly editing file issue: resource busy
    if (is_alp) {
        $_dns_file = '/etc/hosts.wip';
        assert_script_run "cp /etc/hosts $_dns_file";
    }

    script_run "sed -i '/$_vm/d' $_dns_file";
    assert_script_run "echo '$_ip $_vm' >> $_dns_file";
    assert_script_run "cp $_dns_file /etc/hosts" if (is_alp);
    save_screenshot;
    record_info("Simple DNS setup in /etc/hosts for $_ip $_vm is successful!", script_output("cat /etc/hosts"));
}

sub update_simple_dns_for_all_vm {
    my $_vnet = shift;

    my $_cmd = "virsh list --all | grep -e sles -e opensuse -e alp -i | awk \'{print \$2}\'";
    my $_vms = script_output($_cmd, 30, type_command => 0, proceed_on_failure => 0);
    check_guest_ip("$_", net => $_vnet) foreach (split(/\n+/, $_vms));
}

sub validate_guest_status {
    my ($guest, %args) = @_;
    my $timeout = $args{timeout} // "180";
    #Ensure the given guest as running status
    if (script_run("virsh list --all | grep $guest | grep running") ne 0) {
        assert_script_run "virsh list --all | grep $guest";
        save_screenshot;
        die "Error: $guest should keep running, please check manually!";
    } else {
        #Ensure the ICMP PING responses for the given guest
        die "Error: Ping $guest failed, please check manually!" if (script_retry("ping -c5 $guest", delay => 30, retry => 6, timeout => $timeout) ne 0);
        #Ensure the SSH connection for the given guest
        die "Error: SSH $guest failed, please check manually!" if (script_retry("nc -zv $guest 22", delay => 30, retry => 6, timeout => $timeout) ne 0);
    }
}

1;
