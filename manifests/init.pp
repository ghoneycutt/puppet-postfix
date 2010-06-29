# Class: postfix
#
# This module manages postfix, our defacto MTA
#
# Requires:
#   class puppet
#   $postfix_type must be set for systems that are not your basic mail client
#
class postfix {

    include puppet

    # send prod boxes email to root@ and preprod to root-preprod@
    $root_mail = $envSilo ? {
        prod    => "root@$lsbProvider.com",
        default => "root-preprod@$lsbProvider.com",
    }

    # default is root, which is set above by $root_mail
    $postmaster_mail = $envSilo ? {
        prod    => "postmaster@$lsbProvider.com",
        default => "root",
    }

    # 20090826 - GH
    # How we are handling this class and its subclasses is not consistent
    # with our code. Instead of setting the $postfix_type variable in the
    # node definition, we should just include postfix::foo and combine
    # postfix::client into the base postfix class
    #
    # default class is that of a client
    case $postfix_type {
        rt:         { include postfix::rt }
        default:    { include postfix::client }
    } # case $postfix_type
    
    package {
        "postfix": ;
        "mailx":
    } # package

    file {
        "/etc/mailname":
            require => Package["postfix"],
            notify  => Service["postfix"],
            content => "$fqdn\n";
        "/etc/postfix/aliases":
            require => Package["postfix"],
            content => template("postfix/aliases.erb");
            #notify  => Exec["postalias"];
        "/etc/aliases":
            ensure  => link,
            target  => "/etc/postfix/aliases";
        "/etc/postfix/roleaccount_exceptions":
            source  => "puppet:///modules/postfix/roleaccount_exceptions",
            require => Package["postfix"],
            notify  => Exec["postmap-roleaccount_exceptions"];
    } # file

    exec {
#        "postalias":
#            command     => "/usr/sbin/postalias /etc/postfix/aliases",
#            require     => File["/etc/postfix/aliases"],
#            refreshonly => true;
        "postmap-roleaccount_exceptions":
            command     => "/usr/sbin/postmap /etc/postfix/roleaccount_exceptions",
            require     => File["/etc/postfix/roleaccount_exceptions"],
            refreshonly => true;
    } # exec

    service { "postfix":
        ensure  => running,
        enable  => true,
        require => Package["postfix"], ;
    } # service

    # Definition: postfix::post_files
    #
    # setup postfix with a custom main.cf and master.cf 
    #
    # Actions:
    #   setup postfix with a custom main.cf and master.cf
    #
    # Sample Usage:
    #   post_files { "client": }
    #
    define post_files() {
        File {
            require => Package["postfix"],
            notify  => Service["postfix"],
        }

        file { 
            "/etc/postfix/master.cf":
                source => [ "puppet:///modules/postfix/$name/master.cf-$operatingsystem", "puppet:///modules/postfix/$name/master.cf" ],
                links  => follow;
            "/etc/postfix/main.cf":
                source => "puppet:///modules/postfix/$name/main.cf";
        } # file
    } # define post_files

    # Definition: postfix::postalias    
    #
    # postalias will run postalias on your alias file. If you do not specify one
    # the default of /etc/postfix/aliases is used.
    #
    # Parameters:
    #   $aliasfile - path to an alias file, defaults to /etc/postfix/aliases
    #
    # Requires:
    #   a file{} of your aliases already defined
    #
    # Sample Usage:
    #   postalias { "client": }
    #
    define postalias($aliasfile = undef) {
        # if aliasfile is unspecified, use /etc/postfix/aliases
        if $aliasfile {
            $myaliasfile = $aliasfile
        } else {
            $myaliasfile = "/etc/postfix/aliases"
        }

        exec { "postalias-$name":
            command     => "/usr/sbin/postalias $myaliasfile",
            require     => [ Package["postfix"], File["$myaliasfile"]],
            creates     => "${puppet::semaphores}/postalias-$name",
        } # exec
    } # define postalias

} # class postfix

# Class: postfix::client
#
# generic class for all clients
#
class postfix::client inherits postfix {
    post_files { "client": }
    postalias { "client": }

    # this file is only present for client config
    file { "/etc/postfix/sender_regexp":
        require => Package["postfix"],
        notify  => Service["postfix"],
        content => template("postfix/client-sender_regexp.erb"),
    }
} # class postfix::client

# Class: postfix::rt
#
# used by systems running RT
#
class postfix::rt inherits postfix {

    include generic

    # we want mail stats for RT nodes
    include postfix::pflogsumm

    realize Generic::Mkuser[rt]

    post_files { "rt": }
    postalias { "rt": aliasfile => "/home/rt/aliases" }

    file { "/home/rt/aliases": 
        source  => "puppet:///modules/rt/aliases",
        owner   => "rt",
        group   => "rt",
        ensure  => present,
        require => Generic::Mkuser[rt],
    } # file

#    Exec["postalias"] {
#        require +> File["/home/rt/aliases"],
#    } # Exec
} # class postfix::rt

#
# pflogsumm - gives us mail stats
#
class postfix::pflogsumm inherits postfix {

    package { "postfix-pflogsumm": }

    cron { "pflogsumm_daily":
        command => "/usr/sbin/pflogsumm -d yesterday /var/log/maillog 2>&1 |/bin/mail -s \"[Daily mail stats for `uname -n`]\" postmast@$lsbProvider.com",
        user    => "root",
        hour    => "0",
        minute  => "10",
        require => Package["postfix-pflogsumm", "postfix"],
    } # cron
} # class postfix::pflogsumm
