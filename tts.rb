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
    :channels       => nil,
    :allowed_tags   => "irc_privmsg",
    :ignore_nicks   => "weechat",
    :mute           => "off",
    :mp3_path       => "/tmp/",
    :keyfile        => nil,
  }

  def initialize()
    DEFAULT_OPTIONS.each_pair do |option, value|
      # install default options if needed.
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

    pid = fork do
      `mpg123 -q #{filename} && rm #{filename}`
    end
  end

  # Remove unwanted URLs from message
  def sanitize( message )
    urls = URI.extract(message)

    return message if urls.length.zero?

    urls.each do |url|
      next if URI.parse(url).class != URI::HTTP # Ignore URI::General etc

      host = URI.parse(url).host
      host = host.start_with?('www.') ? host[4..-1] : host
      message = message.gsub(url, host)
    end

    return message
  end

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

    return WEECHAT_RC_OK

  rescue => err
    print_err err
    return WEECHAT_RC_OK
  end

  def toggle_mute(data, buffer, args)
    bool = Weechat.config_get_plugin('mute') == 'on' ? 'off' : 'on'
    Weechat.config_set_plugin( 'mute', bool )
    print_info "tts mute toggled #{bool}"
  end

  def print_info(message)
    Weechat.print '', "%sTTS\t%s" % [
      Weechat.color('yellow'),
      message
    ]
  end

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

  return Weechat::WEECHAT_RC_OK
rescue => err
  Weechat.print '', "tts_notify: %s, %p" % [
    err.class.name,
    err.message
  ]

  return Weechat::WEECHAT_RC_ERROR
end

require 'forwardable'
extend Forwardable
def_delegators :$tts, :read, :toggle_mute
