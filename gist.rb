#!/usr/bin/env ruby

# = USAGE
#  gist < file.txt
#  echo secret | gist -p  # or --private
#  echo "puts :hi" | gist -t rb
#  gist script.py
#
# = INSTALL
# RubyGem:
#     gem install gist
# Old school:
#     curl -s http://github.com/defunkt/gist/raw/master/gist.rb > gist &&
#     chmod 755 gist &&
#     mv gist /usr/local/bin/gist

require 'open-uri'
require 'net/http'
require 'optparse'

module Gist
  extend self

  VERSION = "1.0.0"

  GIST_URL   = 'http://gist.github.com/%s.txt'
  CREATE_URL = 'http://gist.github.com/gists'

  PROXY = ENV['HTTP_PROXY'] ? URI(ENV['HTTP_PROXY']) : nil
  PROXY_HOST = PROXY ? PROXY.host : nil
  PROXY_PORT = PROXY ? PROXY.port : nil

  # Parses command line arguments and does what needs to be done.
  def parse(args)
    private_gist = false
    gist_extension = nil

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: gist [options] [filename or stdin]"

      opts.on('-p', '--private', 'Make the gist private') do
        private_gist = true
      end

      t_desc = 'Set syntax highlighting of the Gist by file extension'
      opts.on('-t', '--type [EXTENSION]', t_desc) do |extension|
        gist_extension = '.' + extension
      end

      opts.on('-h', '--help', 'Display this screen') do
        puts opts
        exit
      end
    end

    opts.parse!(args)

    begin
      if $stdin.tty?
        # Run without stdin.

        # No args, print help.
        puts opts if args.empty?
        exit

        # Check if arg is a file. If so, grab the content.
        if File.exists?(file = args[0])
          input = File.read(file)
          gist_extension = File.extname(file) if file.include?('.')
        else
          abort "Can't find #{file}"
        end
      else
        # Read from standard input.
        input = $stdin.read
      end

      puts Gist.write(input, private_gist, gist_extension)
    rescue => e
      warn e
      puts opts
    end
  end

  # Create a gist on gist.github.com
  def write(content, private_gist = false, gist_extension = nil)
    url = URI.parse(CREATE_URL)

    # Net::HTTP::Proxy returns Net::HTTP if PROXY_HOST is nil
    proxy = Net::HTTP::Proxy(PROXY_HOST, PROXY_PORT)
    req = proxy.post_form(url, data(nil, gist_extension, content, private_gist))

    copy req['Location']
  end

  # Given a gist id, returns its content.
  def read(gist_id)
    open(GIST_URL % gist_id).read
  end

private
  # Tries to copy passed content to the clipboard.
  def copy(content)
    case RUBY_PLATFORM
    when /darwin/
      return content unless system("which pbcopy 2> /dev/null")
      IO.popen('pbcopy', 'r+') { |clip| clip.print content }
      `open #{content}`
    when /linux/
      return content unless system("which xclip 2> /dev/null")
      IO.popen('xclip -sel clip', 'r+') { |clip| clip.print content }
    when /i386-cygwin/
      return content if `which putclip`.strip == ''
      IO.popen('putclip', 'r+') { |clip| clip.print content }
    end

    content
  end

  # Give a file name, extension, content, and private boolean, returns
  # an appropriate payload for POSTing to gist.github.com
  def data(name, ext, content, private_gist)
    return {
      'file_ext[gistfile1]'      => ext,
      'file_name[gistfile1]'     => name,
      'file_contents[gistfile1]' => content
    }.merge(private_gist ? { 'action_button' => 'private' } : {}).merge(auth)
  end

  # Returns a hash of the user's GitHub credentials if see.
  # http://github.com/guides/local-github-config
  def auth
    user  = `git config --global github.user`.strip
    token = `git config --global github.token`.strip

    user.empty? ? {} : { :login => user, :token => token }
  end
end

if $0 == __FILE__
  Gist.parse(ARGV)
end
