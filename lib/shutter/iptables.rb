module Shutter
  module Firewall
    class IPTables
      RULES_DMZ_BLOCK         = "# [RULES:DMZ]"
      RULES_FORWARD_BLOCK     = "# [RULES:FORWARD]"
      RULES_POSTROUTING_BLOCK = "# [RULES:POSTROUTING]"
      RULES_BASTARDS_BLOCK    = "# [RULES:BASTARDS]"
      RULES_PUBLIC_BLOCK      = "# [RULES:PUBLIC]"
      RULES_ALLOWIP_BLOCK     = "# [RULES:ALLOWIP]"
      RULES_PRIVATE_BLOCK     = "# [RULES:PRIVATE]"
      RULES_FAIL2BAN_BLOCK    = "# [RULES:FAIL2BAN]"
      RULES_JAIL_BLOCK        = "# [RULES:JAIL]"
      CHAIN_FAIL2BAN_BLOCK    = "# [CHAIN:FAIL2BAN]"

      def initialize(path)
        @path = path
        @base = read("base.ipt",false).join("\n")
        @iface_forward = read("iface.forward")
        @ports_private = read("ports.private")
        @ports_public = read("ports.public")
        @ip_allow = read("ip.allow")
        @ip_deny = read("ip.deny")
        @dmz_device = read("iface.dmz")
        @os = Shutter::OS.new
      end

      def base_sub(block,content)
        @base = @base.gsub(/#{Regexp.quote(block)}/, content)
      end

      def generate
        base_sub(RULES_DMZ_BLOCK,          dmz_device_block)
        base_sub(RULES_FORWARD_BLOCK,      forward_block)
        base_sub(RULES_POSTROUTING_BLOCK,  postrouting_block)
        base_sub(RULES_BASTARDS_BLOCK,     deny_ip_block)
        base_sub(RULES_PUBLIC_BLOCK,       allow_public_port_block)
        base_sub(RULES_ALLOWIP_BLOCK,      allow_ip_block)
        base_sub(RULES_PRIVATE_BLOCK,      allow_private_port_block)
        base_sub(RULES_FAIL2BAN_BLOCK,     fail2ban_rules_block)
        base_sub(RULES_JAIL_BLOCK,         jail_rules_block)
        base_sub(CHAIN_FAIL2BAN_BLOCK,     fail2ban_chains_block)
        clean
      end

      def to_s
        @base
      end

      def clean
        @base = @base.gsub(/^#.*$/, "")
        @base = @base.gsub(/^$\n/, "")
        # Add a newline at the end
        @base += "\n"
      end

      def read(file, filter=true)
        #puts "Reading: #{@path}/#{file}"
        lines = File.read("#{@path}/#{file}").split("\n")
        # Doesn't work with 1.8.x
        # lines.keep_if{ |line| line =~ /^[a-z0-9].+$/ } if filter
        # so since we are iterating through this, well handle the stripping as well
        # lines.map { |line| line.strip }
        newlines = []
        lines.each do |line|
          if filter
            newlines << line.strip if line =~ /^[a-z0-9].+$/
          else
            newlines << line.strip
          end
        end
        newlines
      end

      def save
        puts self.generate
      end

      def restore(persist = false)
        rules = self.generate
        IO.popen("#{iptables_restore}", "r+") do |iptr|
          iptr.puts self.generate ; iptr.close_write
        end
      end

      def persist(pfile)
        File.open(pfile, "w") do |f|
          f.write(@base)
        end
      end

      ###
      ### IPTables Commands
      ###
      def iptables_save
        @iptable_save ||= `"#{@os.iptables_save}"`
      end

      def iptables_restore
        "#{@os.iptables_restore}"
      end

      ###
      ### Check to see if base and iptables-save content match
      ###
      def check
        gen_rules = filter_and_sort(generate)
        ips_rules = filter_and_sort(iptables_save)
        extra_rules = ips_rules - gen_rules
        extra_rules.empty?
      end

      ###
      ### Block Generation
      ###
      def forward_block
        content = ""
        @iface_forward.each do |line|
          src, dst = line.split(' ')
          content += self.forward_content(src,dst)
        end
        content
      end

      def postrouting_block
        masq_ifaces = []
        content = ""
        @iface_forward.each do |line|
          src, dst = line.split(' ')
          content += self.postrouting_content(dst) unless masq_ifaces.include?(dst)
          masq_ifaces << dst
        end
        content
      end

      def allow_private_port_block
        content = ""
        @ports_private.each do |line|
          port,proto = line.split
          content += self.allow_private_port_content(port, proto)
        end
        content
      end

      def allow_public_port_block
        content = ""
        @ports_public.each do |line|
          port,proto = line.split
          raise "Invalid port in port.allow" unless port =~ /^[0-9].*$/
          raise "Invalid protocol in port.allow" unless proto =~ /^(tcp|udp)$/
          content += self.allow_public_port_content(port, proto)
        end
        content
      end

      def allow_ip_block
        content = ""
        @ip_allow.each do |line|
          raise "Invalid IP address in ip.allow" unless line =~ /^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}(\/[0-9]{0,2})*$/
          content += self.allow_ip_content(line)
        end
        content
      end

      def deny_ip_block
        content = ""
        @ip_deny.each do |line|
          raise "Invalid IP address in ip.deny" unless line =~ /^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}(\/[0-9]{0,2})*$/
          content += self.deny_ip_content(line)
        end
        content
      end

      def dmz_device_block
        content = ""
        @dmz_device.each do |line|
          raise "Invalid device in iface.dmz" unless line =~ /^[a-z][a-z0-9].*$/
          content += self.dmz_device_content(line)
        end
        content
      end

      def fail2ban_chains_block
        iptables_save.scan(/^:fail2ban.*$/).join("\n")
      end

      def fail2ban_rules_block
        iptables_save.scan(/^-A fail2ban.*$/).join("\n")
      end

      def jail_rules_block
        lines = iptables_save.scan(/^-A Jail.*$/)
        lines << "-A Jail -j RETURN\n" unless lines.last =~ /-A Jail -j RETURN/
        lines.join("\n")
      end   

      ###
      ### Block Content
      ###
      def forward_content(src,dst)
        rule =  "-A FORWARD -i #{src} -o #{dst} -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT\n"
        rule += "-A FORWARD -i #{dst} -o #{src} -m state --state RELATED,ESTABLISHED -j ACCEPT\n"
        rule
      end

      def postrouting_content(iface)
        "-A POSTROUTING -o #{iface} -j MASQUERADE\n"
      end

      def allow_private_port_content(port, proto)
        "-A Private -m state --state NEW -p #{proto} -m #{proto} --dport #{port} -j RETURN\n"
      end

      def allow_public_port_content(port, proto)
        "-A Public -m state --state NEW -p #{proto} -m #{proto} --dport #{port} -j ACCEPT\n"
      end

      def allow_ip_content(ip)
        "-A AllowIP -m state --state NEW -s #{ip} -j Allowed\n"
      end

      def deny_ip_content(ip)
        "-A Bastards -s #{ip} -j DropBastards\n"
      end

      def dmz_device_content(iface)
        "-A Dmz -i #{iface} -j ACCEPT\n"
      end

      private
      ###
      ### Filter and sort iptables-save for checking
      ###
      def filter_and_sort(content)
        filtered = content.scan(/^[:-].*$/).sort
        # Make sure that we remove (gsub) the counts on the chains and remove any
        # trailing whitespace and newlines
        filtered.map {|x| x.gsub(/\ \[.*\]/,"").split(' ').sort.join.strip}
      end

    end
  end
end