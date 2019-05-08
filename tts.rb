# Walker Griggs
# walker@walkergriggs.com
# 
# TTS
# ---
#                                                                               .
# Run incoming messages through Google's text-to-speech api and play the resulting
# soundclip with mpg123. Plugin scaffolding inspired from Mahlon E. Smith's
# amqp_notify plugin.
#
#     https://weechat.org/scripts/source/amqp_notify.rb.html/
#
# The user is expected to provide their own keyfile for a GCP service account and
# will incur any associated charges.
#
#     https://cloud.google.com/docs/authentication
#     https://cloud.google.com/text-to-speech/pricing
#
# Installing
# ----------
#
# TTS requires Google's "google-cloud-text_to_speech" gem. Place this script into
# your ~/.weechat/ruby directory and load the script.
#     
#     /ruby load tts.rb
#
# Alternatively, you could load the script directly
#
#     /script load PATH/TO/TTS.RB
#
# Options
# -------
#
# plugins.var.ruby.tts.keyfile
#
#     The path to the Google service account keyfile.
#     Defaults to an empty string.
#
# plugins.var.ruby.tts.channels
#
#     A comma separated list of channels (with prepended hash or hashes)
#     Defaults to an empty string.
#
# plugins.var.ruby.tts.allowed_tags
#
#     A comma separated list of allowed tags for messages to read aloud. All other
#     messages will be ignored.
#     Defaults to 'irc_privmsg'
#
# plugins.var.ruby.tts.ignored_nicks
#
#     A comma seperated list of nicks to ignore.
#     Defaults to 'weechat'
#
# plugins.var.ruby.tts.mute
#
#     A global on/off toggle.
#     Defaults to 'off'
#
# plugins.var.ruby.tts.mp3_path
#
#     A temporary path to place MP3 files while they're being read before getting deleted.
#     Defaults to '/tmp/'

class TTS
  include Weechat

  attr_reader :client

  SIGNATURE = [
    'tts',
    'Walker Griggs',
    '0.1',
    'GPL3',
    'Text to speech with Google API',
    '',
    'UTF-8'
  ]

  DEFAULT_OPTIONS = {
    :channels       => '',
    :allowed_tags   => "irc_privmsg",
    :ignore_nicks   => "weechat",
    :mute           => "off",
    :mp3_path       => "/tmp/",
    :keyfile        => '',
  }

  def initialize()
    DEFAULT_OPTIONS.each_pair do |option, value|
      if Weechat.config_is_set_plugin( option.to_s ).zero?
        self.print_info "Setting value '%s' to %p" % [ option, value ]
        Weechat.config_set_plugin( option.to_s, value.to_s )
      end

      val = Weechat.config_get_plugin( option.to_s )
      instance_variable_set( "@#{option}".to_sym, val )
      self.class.send( :attr, option.to_sym, true )
    end

    authenticate
  end

  # Create new client using given keyfile
  def authenticate()
    @client = Google::Cloud::TextToSpeech.new credentials: self.keyfile
  end

  # Use Google API to synthesize speech from given messege
  def synthesize(message)
    input = { text: message }
    voice = { language_code: "en-US" }
    audio_config = { audio_encoding: :MP3 }

    @client.synthesize_speech(input, voice, audio_config)
  end

  # Write MP3 byte string to file
  def to_file(message, filename)
    speech = self.synthesize message
   
    File.open(filename, "wb") do |f|
      f.write(speech.audio_content)
    end
  end

  # Play message using mpg123
  def play(message)
    `which mpg123`
    if $?.to_i != 0
      print_err "mpg123 executable not found in $PATH."
      exit 1
    end

    filename = self.mp3_path + SecureRandom.hex + ".mp3"
    self.to_file(message, filename)

    # Fork off the mpg process and delete MP3 on successful exit
    # TODO: Pipe message over to external process so forked processes are synchronous
    #       without blocking Weechat processes.
    pid = fork do
      `mpg123 -q #{filename} && rm #{filename}`
    end
  end

  # Remove unwanted URLs from message
  def sanitize( message )
    urls = URI.extract(message)

    # Return early no URLs are foudnd.
    return message if urls.length.zero?

    urls.each do |url|
      next if URI.parse(url).class != URI::HTTP # Ignore URI::General etc

      host = URI.parse(url).host
      host = host.start_with?('www.') ? host[4..-1] : host
      message = message.gsub(url, host)
    end

    message
  end

  # Filter out messages and format, synthesize, and read the rest.
  def read( data, buffer, date, tags, visible, highlight, prefix, message )

    # Return immediately if muted
    return WEECHAT_RC_OK if Weechat.config_get_plugin('mute') == "on"

    # Grab the channel metadata.
    data = {}
    %w[ away type channel server ].each do |meta|
      data[ meta.to_sym ] = Weechat.buffer_get_string( buffer, "localvar_#{meta}" );
    end

    # Return if message type isn't allowed
    tags    = tags.split( ',' )
    allowed = self.allowed_tags.split( ',' )
    return WEECHAT_RC_OK if (tags & allowed).empty?

    # Grab the nick if it's tagged, otherwise 'anon'.
    # Return if the message is sent from one of the ignored nicks
    nick = tags.find{ |e| /^nick_/=~e }
    data[ :nick ] = !nick.nil? ? nick[5..] : "anon"
    return WEECHAT_RC_OK if self.ignore_nicks.include?(data[ :nick ])

    # Return if message isn't from configured channels
    return WEECHAT_RC_OK unless self.channels.include?(data[ :channel ])

    # Sanitize and format the message
    message = sanitize(message)
    message.prepend("#{data[ :nick ]} says, ")

    # Fork mpg123 into new process and play mp3 file
    play(message)

    WEECHAT_RC_OK

  rescue => err
    print_err err
    WEECHAT_RC_OK
  end

  # Flip the global on/off mute switch.
  def toggle_mute(data, buffer, args)
    bool = Weechat.config_get_plugin('mute') == 'on' ? 'off' : 'on'
    Weechat.config_set_plugin( 'mute', bool )
    print_info "tts mute toggled #{bool}"
  end

  # Print out given message
  def print_info(message)
    Weechat.print '', "%sTTS\t%s" % [
      Weechat.color('yellow'),
      message
    ]
  end

  # Print out given error
  def print_err(err)
    Weechat.print '', "%sTTS\t%s - %s" % [
      Weechat.color('red'),
      err.class.name,
      err.message
    ]
  end
end

def weechat_init
  require 'rubygems'
  require 'google/cloud/text_to_speech'

  Weechat::register *TTS::SIGNATURE

  $tts = TTS.new
  Weechat.hook_print( '', '', '', 1, 'read', '' )
  Weechat.hook_command('tts-toggle-mute', 'mute/unmute tts', '', '', '', 'toggle_mute', '' )

  Weechat::WEECHAT_RC_OK
rescue => err
  Weechat.print '', "tts_notify: %s, %p" % [
    err.class.name,
    err.message
  ]
  
  Weechat::WEECHAT_RC_ERROR
end

require 'forwardable'
extend Forwardable
def_delegators :$tts, :read, :toggle_mute

__END__
__LICENSE__

Copyright (c) 2019, Walker Griggs <walker@walkergriggs.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the author nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE., WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
