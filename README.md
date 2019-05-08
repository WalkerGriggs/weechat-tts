# TTS
## Weechat text-to-speech With Google's API


### TTS

Run incoming messages through Google's text-to-speech api and play the resulting
soundclip with mpg123. Plugin scaffolding inspired from Mahlon E. Smith's
amqp_notify plugin.

 - https://weechat.org/scripts/source/amqp_notify.rb.html/

The user is expected to provide their own keyfile for a GCP service account and
will incur any associated charges.

 - https://cloud.google.com/docs/authentication
 - https://cloud.google.com/text-to-speech/pricing

### Installing

TTS requires Google's "google-cloud-text_to_speech" gem. Place this script into
your ~/.weechat/ruby directory and load the script.

```/ruby load tts.rb```

Alternatively, you could load the script directly

```/script load PATH/TO/TTS.RB```

Options
-------

```plugins.var.ruby.tts.keyfile```

 - The path to the Google service account keyfile.
 - Defaults to an empty string.

```plugins.var.ruby.tts.channels```

 - A comma separated list of channels (with prepended hash or hashes)
 - Defaults to an empty string.

```plugins.var.ruby.tts.allowed_tags```

 - A comma separated list of allowed tags for messages to read aloud. All other
   messages will be ignored.
 - Defaults to 'irc_privmsg'

```plugins.var.ruby.tts.ignored_nicks```

 - A comma seperated list of nicks to ignore.
 - Defaults to 'weechat'

```plugins.var.ruby.tts.mute```

 - A global on/off toggle.
 - Defaults to 'off'

```plugins.var.ruby.tts.mp3_path```

 - A temporary path to place MP3 files while they're being read before getting deleted.
 - Defaults to '/tmp/'
