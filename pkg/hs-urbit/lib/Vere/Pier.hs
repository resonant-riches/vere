{-# OPTIONS_GHC -Wwarn #-}

module Vere.Pier where

import Data.Acquire
import UrbitPrelude
import Vere.Pier.Types
import Data.Conduit

import System.Directory   (createDirectoryIfMissing)
import System.Posix.Files (ownerModes, setFileMode)
import Vere.Log           (EventLog)
import Vere.Serf          (Serf, SerfState(..))

import qualified System.Entropy as Ent
import qualified Vere.Log       as Log
import qualified Vere.Serf      as Serf


--------------------------------------------------------------------------------

ioDrivers = [] :: [IODriver]

setupPierDirectory :: FilePath -> IO ()
setupPierDirectory shipPath = do
   for_ ["put", "get", "log", "chk"] $ \seg -> do
     let pax = shipPath <> "/.urb/" <> seg
     createDirectoryIfMissing True pax
     setFileMode pax ownerModes

{-
data Pier = Pier
  { computeQueue  :: TQueue Ovum
  , persistQueue  :: TQueue (Writ [Eff])
  , releaseQueue  :: TQueue (Writ [Eff])
  , log           :: EventLog
  , driverThreads :: [(Async (), Perform)]
  , portingThread :: Async ()
  }
-}


--------------------------------------------------------------------------------

genEntropy :: IO Word512
genEntropy = fromIntegral . view (from atomBytes) <$> Ent.getEntropy 64

generateBootSeq :: Ship -> Pill -> IO BootSeq
generateBootSeq ship Pill{..} = do
    ent <- genEntropy
    let ovums = preKern ent <> pKernelOvums <> pUserspaceOvums
    pure $ BootSeq ident pBootFormulas ovums
  where
    ident       = LogIdentity ship True (fromIntegral $ length pBootFormulas)
    preKern ent = [ Ovum (Path ["", "term", "1"]) (Boot $ Fake $ who ident)
                  , Ovum (Path ["", "arvo"])      (Whom ship)
                  , Ovum (Path ["", "arvo"])      (Wack ent)
                  ]


--------------------------------------------------------------------------------

{-
    This is called to make a freshly booted pier. It assigns an identity
    to an event log and takes a chill pill.
-}
boot :: FilePath -> FilePath -> Ship
     -> (Serf -> EventLog -> SerfState -> IO a)
     -> IO a
boot pillPath top ship act = do
  let logPath = top <> "/.urb/log"

  pill <- loadFile @Pill pillPath >>= \case
            Left l  -> error (show l)
            Right p -> pure p

  seq@(BootSeq ident x y) <- generateBootSeq ship pill

  with (Log.new logPath ident) $ \log -> do
      serf             <- Serf.startSerfProcess top
      (events, serfSt) <- Serf.bootFromSeq serf seq
      Serf.requestSnapshot serf serfSt
      traceM "writeJobs"
      writeJobs log (fromList events)
      act serf log serfSt

{-
    What we really want to do is write the log identity and then do
    normal startup, but writeIdent requires a full log state
    including input/output queues.
-}
resume :: FilePath -> (Serf -> EventLog -> SerfState -> IO a) -> IO a
resume top act = do
  with (Log.existing (top <> "/.urb/log")) $ \log -> do
    traceM "But why?"
    serf   <- Serf.startSerfProcess top
    traceM "What"
    serfSt <- Serf.replay serf log
    traceM "is"

    Serf.requestSnapshot serf serfSt
    traceM "happening"

    act serf log serfSt

writeJobs :: EventLog -> Vector Job -> IO ()
writeJobs log !jobs = do
    expect <- Log.nextEv log
    events <- fmap fromList $ traverse fromJob (zip [expect..] $ toList jobs)
    Log.appendEvents log events
  where
    fromJob :: (EventId, Job) -> IO Atom
    fromJob (expectedId, job) = do
        guard (expectedId == jobId job)
        pure $ jam $ jobPayload job

    jobPayload :: Job -> Noun
    jobPayload (RunNok (LifeCyc _ m n)) = toNoun (m, n)
    jobPayload (DoWork (Work _ m d o))  = toNoun (m, d, o)


-- Run Pier --------------------------------------------------------------------

{-
performCommonPierStartup :: Serf.Serf
                         -> TQueue Ovum
                         -> TQueue (Writ [Eff])
                         -> TQueue (Writ [Eff])
                         -> LogState
                         -> IO Pier
performCommonPierStartup serf computeQ persistQ releaseQ logState = do
  for ioDrivers $ \x -> do
    bootMessage <- bornEvent x
    atomically $ writeTQueue computeQ bootMessage

  driverThreads <- for ioDrivers $ \x -> do
    startDriver x (writeTQueue computeQ)

  -- TODO: Don't do a bunch of extra work; we send all effects to all drivers
  portingThread <- async $ do
    forever $ do
      r <- atomically (readTQueue releaseQ)
      for_ driverThreads $ \(_, k) ->
        for_ (payload r) $ \eff ->
          k eff

  Serf.workerThread serf (readTQueue computeQ) undefined

  pure (Pier{..})
-}


-- Persist Thread --------------------------------------------------------------

data PersistExn = BadEventId EventId EventId
  deriving Show

instance Exception PersistExn where
  displayException (BadEventId expected got) =
    unlines [ "Out-of-order event id send to persist thread."
            , "\tExpected " <> show expected <> " but got " <> show got
            ]

runPersist :: EventLog
           -> TQueue (Writ [Eff])
           -> (Writ [Eff] -> STM ())
           -> Acquire ()
runPersist log inpQ out = do
    mkAcquire runThread cancelWait
    pure ()
  where
    cancelWait :: Async () -> IO ()
    cancelWait tid = cancel tid >> wait tid

    runThread :: IO (Async ())
    runThread = asyncBound $ forever $ do
        writs  <- atomically (toNullable <$> getBatchFromQueue)
        events <- validateWritsAndGetAtom writs
        Log.appendEvents log events
        atomically $ traverse_ out writs

    validateWritsAndGetAtom :: [Writ [Eff]] -> IO (Vector Atom)
    validateWritsAndGetAtom writs = do
        expect <- Log.nextEv log
        fmap fromList
            $ for (zip [expect..] writs)
            $ \(expectedId, Writ{..}) -> do
                unless (expectedId == eventId) $
                    throwIO (BadEventId expectedId eventId)
                pure (unJam event)

    getBatchFromQueue :: STM (NonNull [Writ [Eff]])
    getBatchFromQueue =
        readTQueue inpQ >>= go . singleton
      where
        go acc =
          tryReadTQueue inpQ >>= \case
            Nothing   -> pure (reverse acc)
            Just item -> go (item <| acc)
