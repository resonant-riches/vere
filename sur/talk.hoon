::
::::  /hoon/talk/sur
  !:
|%
::
::TODO  wrappers around knot for story name, nickname,
::TODO  use different words for different kinds of burdens
::
::>  ||
::>  ||  %query-models
::>  ||
::>    models relating to queries, their results and updates.
::+|
::
++  query                                               ::>  query paths
  $%  {$reader $~}                                      ::<  shared ui state
      {$friend $~}                                      ::<  publicly joined
      {$burden who/ship}                                ::<  duties to share
      {$report $~}                                      ::<  duty reports
      {$circle nom/knot ran/range}                      ::<  story query
      ::TODO  separate stream for just msgs? what about just configs? presences?
      ::      yes!
  ==                                                    ::
  ::TODO  more newlines
++  range  (unit {hed/place tal/(unit place)})          ::<  inclusive msg range
++  place  $%({$da @da} {$ud @ud})                      ::<  @ud/@da for range
++  prize                                               ::>  query result
  $%  $:  $reader                                       ::<  /reader
          gys/(jug char (set partner))                  ::<  glyph bindings
          nis/(map ship cord)                           ::<  nicknames
      ==                                                ::
      {$friend cis/(set circle)}                        ::<  /friend
      {$burden sos/(map knot burden)}                   ::<  /burden
      ::TODO  do we ever use remote things from remote circles?
      {$circle burden}                                  ::<  /circle
  ==                                                    ::
  ::TODO  ++prize-reader {gys nis} etc.
++  rumor                                               ::<  query result change
  $%  $:  $reader                                       ::<  /reader
          $=  dif                                       ::
          $%  {$glyph diff-glyph}                       ::
              {$nick diff-nick}                         ::
          ==                                            ::
      ==                                                ::
      {$friend add/? cir/circle}                        ::<  /friend
      {$burden nom/knot dif/diff-story}                 ::<  /burden
      {$circle dif/diff-story}                          ::<  /circle
  ==                                                    ::
++  burden                                              ::<  full story state
  $:  gaz/(list telegram)                               ::<  all messages
      cos/lobby                                         ::<  loc & rem configs
      pes/crowd                                         ::<  loc & rem presences
  ==                                                    ::
::TODO  deltas into app
++  delta                                               ::
  $%  ::  messaging state                               ::
      {$out cir/circle out/(list thought)}              ::<  msgs into outbox
      {$done num/@ud}                                   ::<  msgs delivered
      ::  shared ui state                               ::
      {$glyph diff-glyph}                               ::<  un/bound glyph
      {$nick diff-nick}                                 ::<  changed nickname
      ::  story state                                   ::
      {$story nom/knot dif/diff-story}                  ::<  change to story
      ::  side-effects                                  ::
      {$init $~}                                        ::<  initialize
      {$observe who/ship}                               ::<  watch burden bearer
      {$react rac/reaction}                             ::<  reaction to action
      {$present hos/ship nos/(set knot) dif/diff-status}::<  send %present cmd
      {$quit ost/bone}                                  ::<  force unsubscribe
  ==                                                    ::
++  diff-glyph  {bin/? gyf/char pas/(set partner)}      ::<  un/bound glyph
++  diff-nick   {who/ship nic/cord}                     ::<  changed nickname
::TODO  separate remote-only diffs, like so:
::++  diff-foobar
::  $?  diff-story
::  $%  {$other-thing ...}
::  ==
++  diff-story                                          ::
  $%  {$new cof/config}                                 ::<  new story
      {$bear bur/burden}                                ::<  new inherited story
      {$burden bur/?}                                   ::<  burden flag
      {$grams gaz/(list telegram)}                      ::<  new/changed msgs
      {$config cir/circle dif/diff-config}              ::<  new/changed config
      {$status pan/partner who/ship dif/diff-status}    ::<  new/changed status
      {$follow sub/? pas/(map partner range)}           ::<  un/subscribe
      {$remove $~}                                      ::<  removed story
  ==                                                    ::
++  diff-config                                         ::>  config change
  ::TODO  maybe just full? think.
  $%  {$full cof/config}                                ::<  set w/o side-effects
      {$source add/? pan/partner}                       ::<  add/rem sources
      {$caption cap/cord}                               ::<  changed description
      {$filter fit/filter}                              ::<  changed filter
      {$secure sec/security}                            ::<  changed security
      {$permit add/? sis/(set ship)}                    ::<  add/rem to b/w-list
      {$remove $~}                                      ::<  removed config
  ==                                                    ::
++  diff-status                                         ::>  status change
  $%  {$full sat/status}                                ::<  fully changed status
      {$presence pec/presence}                          ::<  changed presence
      {$human dif/diff-human}                           ::<  changed name
      {$remove $~}                                      ::<  removed config
  ==                                                    ::
++  diff-human                                          ::>  name change
  $%  {$full man/human}                                 ::<  fully changed name
      {$true tru/(unit (trel cord (unit cord) cord))}   ::<  changed true name
      {$handle han/(unit cord)}                         ::<  changed handle
  ==                                                    ::
::
::>  ||
::>  ||  %reader-communication
::>  ||
::>    broker interfaces for readers.
::+|
::
++  action                                              ::>  user action
  $%  ::  circle configuration                          ::
      {$create nom/knot des/cord sec/security}          ::<  create circle
      {$delete nom/knot why/(unit cord)}                ::<  delete + announce
      {$depict nom/knot des/cord}                       ::<  change description
      {$filter nom/knot fit/filter}                     ::<  change message rules
      {$permit nom/knot inv/? sis/(set ship)}           ::<  invite/banish
      {$source nom/knot sub/? src/(map partner range)}  ::<  un/sub to/from src
      ::  messaging                                     ::
      {$convey tos/(list thought)}                      ::<  post exact
      {$phrase aud/(set partner) ses/(list speech)}     ::<  post easy
      ::  personal metadata                             ::
      {$notify cis/(set circle) pes/presence}           ::<  our presence update
      {$naming cis/(set circle) man/human}              ::<  our name update
      ::  changing shared ui                            ::
      {$glyph gyf/char pas/(set partner) bin/?}         ::<  un/bind a glyph
      {$nick who/ship nic/knot}                         ::<  new identity
  ==                                                    ::
::TODO  don't send reactions, just crash!
++  reaction                                            ::>  user information
  $:  res/?($info $fail)                                ::<  result
      wat/cord                                          ::<  explain
      why/(unit action)                                 ::<  cause
  ==                                                    ::
::
::>  ||
::>  ||  %broker-communication
::>  ||
::>    structures for communicating between brokers.
::+|
::
++  command                                             ::>  effect on story
  $%  {$publish tos/(list thought)}                     ::<  deliver
      {$present nos/(set knot) dif/diff-status}         ::<  status update
      {$bearing $~}                                     ::<  prompt to listen
  ==                                                    ::
::
::>  ||
::>  ||  %circles
::>  ||
::>    messaging targets and their metadata.
::+|
::
++  partner    (each circle passport)                   ::<  message target
++  circle     {hos/ship nom/knot}                      ::<  native target
++  passport                                            ::>  foreign target
  $%  {$twitter p/cord}                                 ::<  twitter handle
  ==                                                    ::
::  circle configurations.                              ::
++  lobby      {loc/config rem/(map circle config)}     ::<  our & srcs configs
++  config                                              ::>  circle config
  $:  src/(set partner)                                 ::<  active sources
      ::TODO  ^ include range? just remove!
      cap/cord                                          ::<  description
      fit/filter                                        ::<  message rules
      con/control                                       ::<  restrictions
  ==                                                    ::
++  filter                                              ::>  content filters
  $:  cas/?                                             ::<  dis/allow capitals
      utf/?                                             ::<  dis/allow non-ascii
      ::TODO  maybe message length
  ==                                                    ::
++  control    {sec/security ses/(set ship)}            ::<  access control
++  security                                            ::>  security mode
  $?  $black                                            ::<  channel, blacklist
      $white                                            ::<  village, whitelist
      $green                                            ::<  journal, author list
      $brown                                            ::<  mailbox, our r, bl w
  ==                                                    ::
::  participant metadata.                               ::
::TODO  think about naming more
++  crowd      {loc/group rem/(map partner group)}      ::<  our & srcs presences
++  group      (map ship status)                        ::<  presence map
++  status     {pec/presence man/human}                 ::<  participant
++  presence                                            ::>  status type
  $?  $gone                                             ::<  absent
      $idle                                             ::<  idle
      $hear                                             ::<  present
      $talk                                             ::<  typing
  ==                                                    ::
++  human                                               ::>  human identifier
  $:  han/(unit cord)                                   ::<  handle
      tru/(unit (trel cord (unit cord) cord))           ::<  true name
  ==                                                    ::
::
::>  ||
::>  ||  %message-data
::>  ||
::>    structures for containing main message data.
::+|
::
++  telegram   {aut/ship tot/thought}                   ::<  who thought
++  thought    {uid/serial aud/audience sam/statement}  ::<  which whom this
++  statement  {wen/@da sep/speech}                     ::<  when what body
++  speech                                              ::>  content body
  $%  {$lin pat/? msg/cord}                             ::<  no/@ text line
      {$url url/purf}                                   ::<  parsed url
      {$exp exp/cord res/(list tank)}                   ::<  hoon line
      {$fat tac/attache sep/speech}                     ::<  attachment
      {$inv inv/? cir/circle}                           ::<  inv/ban for circle
      {$app app/term msg/cord}                          ::<  app message
  ==                                                    ::
++  attache                                             ::>  attachment
  $%  {$name nom/cord tac/attache}                      ::<  named attachment
      {$text (list cord)}                               ::<  text lines
      {$tank (list tank)}                               ::<  tank list
  ==                                                    ::
::
::>  ||
::>  ||  %message-metadata
::>  ||
::     structures for containing message metadata.
::+|
::
++  serial     @uvH                                     ::<  unique identifier
++  audience   (set partner)                            ::<  destinations
--
