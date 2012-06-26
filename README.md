# Shutter

Shutter is a tool that enables system administrators the ability to manage 
iptables firewall settings through simple lists instead of complex iptables commands.  Please note:
This application currently only works with Red Hat based distributions, as the need arrises more 
distributions will be added.

## Installation

Instalation is through the gem package management program. 

    $ gem install shutter

## Usage

Install the gem.
    
    $ gem install shutter

Create the initial configuration files.

    $ shutter --init

Modify the files to meet your required settings.  There are several files:
* **base.ipt:**  The one file to rule them all.  Modifying this file is optional as
it is the template that is used to build the firewall. If you do modify the file,
just make sure you include the appropriate placeholder directives to allow
shutter to dynamically fill in the rules.  It is possible to leave out any unwanted
placeholders.
* **iface.dmz:**  Enter any private interfaces that will be unprotected by the firewall.  One per line.
* **ip.allow:**  A list of IP addresses and ranges that are allowed to access the 'private' ports
* **ip.deny:**  A list of IP addresses and ranges that are denied access to both public and private ports. 
* **ports.private:**  A list of ports and protocols that are available to traffic that passes through the AllowIP chain
* **ports.public:**  A list of ports and protocols that are available publically to everyone except the 'Bastards' listed in ip.deny

Shutter was designed to work with the Fail2ban access monitoring/management tool.  It includes a 
special chain called 'Jail' which is used to insert the jump rules that fail2ban uses to deny access 'on-the-fly'.
To work correctly, you configure fail2ban to use the Jail chain instead of INPUT.

To check your firewall you can run:

    $ shutter --save

This command mimics the 'iptables-save' command which prints the rules out to the screen.  
This does not modify the firewall settings.

To implement the changes, use:

    $ shutter --restore

This command uses 'iptables-restore' under the hood to update the firewall.  You can use the '--persist' option
to make the changes permanent and survive reboots.

More documentation to come...


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
