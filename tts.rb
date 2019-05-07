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
    :ignore_nicks   => ['weechat'],
    :ignore_tags    => 'irc_quit',
  }

  def initialize(keyfile)
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

    authenticate(keyfile)
  end

  def authenticate(keyfile)
    @client = Google::Cloud::TextToSpeech.new credentials: keyfile
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
      print_err "mpg123 executable NOT found. This function only work with POSIX systems.\n Install mpg123 with `brew install mpg123` or `apt-get install mpg123`"
      exit 1
    end

    filename = "/home/wgriggs/Documents/irc2speech/" + SecureRandom.hex + ".mp3"
    self.to_file(message, filename)

    pid = fork do
      `mpg123 -q #{filename}`
    end
  end

  # Remove unwanted URLs from message
  def sanitize( message )
    rgx = /(http|ftp|https):\/\/([\w_-]+(?:(?:\.[\w_-]+)+))([\w\S]*[\w@?^=%&\/~+#-])?/
    message.sub rgx, ''
  end

  def read( data, buffer, date, tags, visible, highlight, prefix, message )
    # Grab the channel metadata.
    data = {}
    %w[ away type channel server ].each do |meta|
      data[ meta.to_sym ] = Weechat.buffer_get_string( buffer, "localvar_#{meta}" );
    end
    data[ :away ] = data[ :away ].empty? ? false : true

    tags = tags.split( ',' )

    # Return if message isn't from configured channels
    return WEECHAT_RC_OK unless self.channels.include?(data[ :channel ])

    # Return if message isn't tagged as a "private message"
    return WEECHAT_RC_OK unless tags.include?("irc_privmsg")

    # Return if the message is sent from one of the ignored nicks
    return WEECHAT_RC_OK if self.ignore_nicks.include?(tags.find{ |e| /^nick_/=~e }[5..])

    # Sanitize and format the message
    message = sanitize(message)

    play(message)

	return WEECHAT_RC_OK

  rescue => err
    print_err err
    return WEECHAT_RC_OK
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
  require "google/cloud/text_to_speech"

  Weechat::register *TTS::SIGNATURE

  keyfile = "/home/wgriggs/Downloads/irc-2-speach-d3ac5cd6b8ca.json"

  $tts = TTS.new keyfile
  Weechat.hook_print( '', '', '', 1, 'read', '' )

  return Weechat::WEECHAT_RC_OK
rescue => err
  Weechat.print '', "tts_notify: %s, %p" % [
    err.class.name,
    err.message
  ]

  Weechat.print '', 'tts_notify: Unable to initialize due to missing dependencies.'
  return Weechat::WEECHAT_RC_ERROR
end

require 'forwardable'
extend Forwardable
def_delegators :$tts, :read
