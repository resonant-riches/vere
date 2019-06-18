module Vere.Worker where

import ClassyPrelude
import Control.Lens
import Data.Void

import System.Exit (ExitCode)

import Data.Noun
import Data.Noun.Atom
import Data.Noun.Jam
import Data.Noun.Poet
import Data.Noun.Pill
import Vere.Pier.Types
import System.Process

import Data.ByteString (hGet)
import Data.ByteString.Unsafe (unsafeUseAsCString)
import Foreign.Ptr (castPtr)
import Foreign.Storable (peek)

import qualified Vere.Log as Log

data Worker = Worker
  { sendHandle :: Handle
  , recvHandle :: Handle
  , process    :: ProcessHandle

  -- , getInput   :: STM (Writ ())
  -- , onComputed :: Writ [Effect] -> STM ()

--  , onExit :: Worker -> IO ()
--  , task       :: Async ()
  }



--------------------------------------------------------------------------------

-- Think about how to handle process exit
-- Tear down subprocess on exit? (terminiteProcess)
startWorkerProcess :: IO Worker
startWorkerProcess =
  do
    (Just i, Just o, _, p) <- createProcess pSpec
    pure (Worker i o p)
  where
    pSpec =
      (proc "urbit-worker" []) { std_in  = CreatePipe
                               , std_out = CreatePipe
                               }

kill :: Worker -> IO ExitCode
kill w = do
  terminateProcess (process w)
  waitForProcess (process w)

work :: Word64 -> Jam -> Atom
work id (Jam a) = jam $ toNoun (Cord "work", id, a)

newtype Job = Job Void
  deriving newtype (Eq, Show, ToNoun, FromNoun)

type EventId = Word64

newtype Ship = Ship Word64 -- @p
  deriving newtype (Eq, Ord, Show, ToNoun, FromNoun)

newtype ShipId = ShipId (Ship, Bool)
  deriving newtype (Eq, Ord, Show, ToNoun, FromNoun)

--------------------------------------------------------------------------------

type Play = Nullable (EventId, Mug, ShipId)

data Plea
    = Play Play
    | Work EventId Mug Job
    | Done EventId Mug [Ovum]
    | Stdr EventId Cord
    | Slog EventId Word32 Tank
  deriving (Eq, Show)

instance ToNoun Plea where
  toNoun = \case
    Play p     -> toNoun (Cord "play", p)
    Work i m j -> toNoun (Cord "work", i, m, j)
    Done i m o -> toNoun (Cord "done", i, m, o)
    Stdr i msg -> toNoun (Cord "stdr", i, msg)
    Slog i p t -> toNoun (Cord "slog", i, p, t)

instance FromNoun Plea where
  parseNoun n =
    parseNoun n >>= \case
      (Cord "play", p) -> parseNoun p <&> \p         -> Play p
      (Cord "work", w) -> parseNoun w <&> \(i, m, j) -> Work i m j
      (Cord "done", d) -> parseNoun d <&> \(i, m, o) -> Done i m o
      (Cord "stdr", r) -> parseNoun r <&> \(i, msg)  -> Stdr i msg
      (Cord "slog", s) -> parseNoun s <&> \(i, p, t) -> Slog i p t
      (Cord tag   , s) -> fail ("Invalid plea tag: " <> unpack (decodeUtf8 tag))

--------------------------------------------------------------------------------

type CompletedEventId = Word64
type NextEventId = Word64

type WorkerState = (EventId, Mug)

type ReplacementEv = (EventId, Mug, Job)
type WorkResult    = (EventId, Mug, [Ovum])
type WorkerResp    = (Either ReplacementEv WorkResult)

-- Exceptions ------------------------------------------------------------------

data WorkerExn
    = BadComputeId EventId WorkResult
    | BadReplacementId EventId ReplacementEv
    | UnexpectedPlay EventId Play
    | BadPleaAtom Atom
    | BadPleaNoun Noun
    | ReplacedEventDuringReplay EventId ReplacementEv
    | WorkerConnectionClosed
    | UnexpectedPleaOnNewShip Plea
    | InvalidInitialPlea Plea
  deriving (Show)

instance Exception WorkerExn

-- Utils -----------------------------------------------------------------------

printTank :: Word32 -> Tank -> IO ()
printTank pri t = print "tank"

guardExn :: Exception e => Bool -> e -> IO ()
guardExn ok = unless ok . throwIO

fromJustExn :: Exception e => Maybe a -> e -> IO a
fromJustExn Nothing  exn = throwIO exn
fromJustExn (Just x) exn = pure x

--------------------------------------------------------------------------------

sendAndRecv :: Worker -> EventId -> Atom -> IO WorkerResp
sendAndRecv w eventId event =
  do
    sendAtom w $ work eventId (Jam event)
    loop
  where
    produce :: WorkResult -> IO WorkerResp
    produce (i, m, o) = do
      guardExn (i /= eventId) (BadComputeId eventId (i, m, o))
      pure $ Right (i, m, o)

    replace :: ReplacementEv -> IO WorkerResp
    replace (i, m, j) = do
      guardExn (i /= eventId) (BadReplacementId eventId (i, m, j))
      pure (Left (i, m, j))

    loop :: IO WorkerResp
    loop = recvPlea w >>= \case
      Play p       -> throwIO (UnexpectedPlay eventId p)
      Done i m o   -> produce (i, m, o)
      Work i m j   -> replace (i, m, j)
      Stdr _ cord  -> print cord >> loop
      Slog _ pri t -> printTank pri t >> loop

sendBootEvent :: LogIdentity -> Worker -> IO ()
sendBootEvent id w = do
  sendAtom w $ jam $ toNoun (Cord "boot", id)


-- the ship is booted, but it is behind. shove events to the worker until it is
-- caught up.
replay :: Worker
       -> WorkerState
       -> LogIdentity
       -> EventId
       -> (EventId -> Word64 -> IO (Vector (EventId, Atom)))
       -> IO ()
replay w (wid, wmug) identity lastCommitedId getEvents = do
  when (wid == 1) (sendBootEvent identity w)

  loop wid
  where
    -- Replay events in batches of 1000.
    loop curEvent = do
      let toRead = min 1000 (1 + lastCommitedId - curEvent)
      when (toRead > 0) do
        events <- getEvents curEvent toRead

        for_ events $ \(eventId, event) -> do
          sendAndRecv w eventId event >>= \case
            (Left ev) -> throwIO (ReplacedEventDuringReplay eventId ev)
            (Right _) -> pure ()

        loop (curEvent + toRead)


bootWorker :: Worker
           -> LogIdentity
           -> Pill
           -> IO ()
bootWorker w identity pill =
  do
    recvPlea w >>= \case
      Play Nil   -> pure ()
      x@(Play _) -> throwIO (UnexpectedPleaOnNewShip x)
      x          -> throwIO (InvalidInitialPlea x)

    -- TODO: actually boot the pill
    undefined

    requestSnapshot w

    -- Maybe return the current event id ? But we'll have to figure that out
    -- later.
    pure ()

resumeWorker :: Worker
             -> LogIdentity
             -> EventId
             -> (EventId -> Word64 -> IO (Vector (EventId, Atom)))
             -> IO ()
resumeWorker w identity logLatestEventNumber eventFetcher =
  do
    ws@(eventId, mug) <- recvPlea w >>= \case
      Play Nil                -> pure (1, Mug 0)
      Play (NotNil (e, m, _)) -> pure (e, m)
      x                       -> throwIO (InvalidInitialPlea x)

    replay w ws identity logLatestEventNumber eventFetcher

    requestSnapshot w

    pure ()

workerThread :: Worker -> IO (Async ())
workerThread w = undefined

requestSnapshot :: Worker -> IO ()
requestSnapshot w =  undefined

-- The flow here is that we start the worker and then we receive a play event
-- with the current worker state:
--
--  <- [%play ...]
--
-- Base on this, the main flow is 
--

  --  [%work ] ->
  --  <- [%slog]
  --  <- [%slog]
  --  <- [%slog]
  --  <- [%work crash=tang]
  --  [%work ] ->  (replacement)
  --  <- [%slog]
  --  <- [%done]
--    [%work eventId mat]

--  response <- recvAtom w


-- Basic Send and Receive Operations -------------------------------------------

sendAtom :: Worker -> Atom -> IO ()
sendAtom w a = hPut (sendHandle w) (unpackAtom a)

atomBytes :: Iso' Atom ByteString
atomBytes = pill . pillBS

packAtom = view (from atomBytes)

unpackAtom :: Atom -> ByteString
unpackAtom = view atomBytes

recvLen :: Worker -> IO Word64
recvLen w = do
  bs <- hGet (recvHandle w) 8
  case length bs of
    -- This is not big endian safe
    8 -> unsafeUseAsCString bs (peek . castPtr)
    _ -> throwIO WorkerConnectionClosed

recvBytes :: Worker -> Word64 -> IO ByteString
recvBytes w = hGet (recvHandle w) . fromIntegral

recvAtom :: Worker -> IO Atom
recvAtom w = do
  len <- recvLen w
  bs <- recvBytes w len
  pure (packAtom bs)

recvPlea :: Worker -> IO Plea
recvPlea w = do
  a <- recvAtom w
  n <- fromJustExn (cue a)      (BadPleaAtom a)
  p <- fromJustExn (fromNoun n) (BadPleaNoun n)
  pure p
