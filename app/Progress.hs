-- | The activity indicator hclean shows on stderr while it is working.
--
-- Scanning a large tree produces no output for a long time, so a spinner with
-- a running count and the directory currently being visited is painted on
-- stderr. It is a terminal affordance: when stderr is not a terminal nothing is
-- painted, so pipes and log files stay clean.
module Progress
  ( Progress(..)
  , ProgressMode(..)
  , withProgress
  , indicatorLine
  , shorten
  , spinnerFrame
  ) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (bracket)
import Control.Monad (when)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import System.Environment (lookupEnv)
import System.IO (hFlush, hIsTerminalDevice, hPutStr, hPutStrLn, stderr)
import Text.Read (readMaybe)

-- | When to show the indicator.
data ProgressMode
  = ProgressAuto    -- ^ Show it on a terminal, once the work looks slow.
  | ProgressAlways  -- ^ Always report progress; off a terminal, as one summary line.
  | ProgressNever   -- ^ Never report progress.
  deriving (Eq, Show)

-- | Handle on a running indicator.
data Progress = Progress
  { progressTick    :: FilePath -> IO ()
    -- ^ Count one item, and remember the path as the thing being worked on.
  , progressMessage :: (Int -> String) -> IO ()
    -- ^ Replace the message, for instance when entering a new phase.
  , progressNote    :: String -> IO ()
    -- ^ Print a line on stderr without the indicator scribbling over it.
  }

-- | What the indicator is currently showing.
data Frame = Frame
  { frameCount   :: !Int
  , frameMessage :: Int -> String
  , framePath    :: FilePath
  }

-- | Wait this long before painting anything, so quick runs stay silent.
startupDelay :: Int
startupDelay = 250000

-- | Repaint interval; also how fast the spinner turns.
tickInterval :: Int
tickInterval = 100000

-- | Run an action with an indicator.
--
-- @message@ renders the count into the line shown while working; @summary@
-- renders the final count into a line printed when progress was asked for but
-- stderr is not a terminal, or 'Nothing' to stay quiet.
withProgress
  :: ProgressMode
  -> (Int -> String)
  -> (Int -> Maybe String)
  -> (Progress -> IO a)
  -> IO a
withProgress mode message summary action = do
  terminal <- hIsTerminalDevice stderr
  width <- terminalWidth
  lock <- newMVar ()
  frame <- newIORef (Frame 0 message "")
  painted <- newIORef False
  let live = terminal && mode /= ProgressNever
      counting = live || mode == ProgressAlways
      progress = Progress
        { progressTick = \path ->
            when counting $
              atomicModifyIORef' frame (\f -> (f { frameCount = frameCount f + 1
                                                 , framePath = path }, ()))
        , progressMessage = \m ->
            atomicModifyIORef' frame (\f -> (f { frameMessage = m }, ()))
        , progressNote = \msg -> withMVar lock $ \_ -> do
            erase width painted
            hPutStrLn stderr msg
        }
  result <-
    if live
      then bracket (forkIO (painter lock frame painted width)) killThread
             (const (action progress))
      else action progress
  withMVar lock (\_ -> erase width painted)
  when (counting && not live) $ do
    n <- frameCount <$> readIORef frame
    maybe (pure ()) (hPutStrLn stderr) (summary n)
  pure result

-- | Repaint the indicator until killed.
painter :: MVar () -> IORef Frame -> IORef Bool -> Int -> IO ()
painter lock frame painted width = threadDelay startupDelay >> loop 0
  where
    loop n = do
      withMVar lock $ \_ -> do
        Frame count message path <- readIORef frame
        hPutStr stderr ('\r' : indicatorLine width (spinnerFrame n) (message count) path)
        hFlush stderr
        writeIORef painted True
      threadDelay tickInterval
      loop (n + 1)

-- | Clear the indicator, but only if there is one on screen: a run that
-- finished before the first paint should leave the terminal untouched.
erase :: Int -> IORef Bool -> IO ()
erase width painted = do
  dirty <- readIORef painted
  when dirty $ do
    hPutStr stderr ('\r' : replicate width ' ' ++ "\r")
    hFlush stderr
    writeIORef painted False

-- | One line of indicator, clipped to @width@ columns.
--
-- The path is dropped entirely rather than shown uselessly short.
indicatorLine :: Int -> Char -> String -> FilePath -> String
indicatorLine width frame message path
  | null path || room < 12 = take width prefix
  | otherwise = prefix ++ "  " ++ shorten room path
  where
    prefix = frame : ' ' : message
    room = width - length prefix - 2

-- | Clip a path to @width@ characters, keeping the end, which is the
-- informative half.
shorten :: Int -> FilePath -> String
shorten width path
  | width <= 0 = ""
  | length path <= width = path
  | width <= 3 = replicate width '.'
  | otherwise = "..." ++ drop (length path - width + 3) path

-- | The spinner, in ASCII so it survives any terminal encoding.
spinnerFrame :: Int -> Char
spinnerFrame n = "|/-\\" !! (n `mod` 4)

-- | Terminal width from @COLUMNS@, clamped to something sensible.
terminalWidth :: IO Int
terminalWidth = do
  columns <- lookupEnv "COLUMNS"
  pure $ case columns >>= readMaybe of
    Just n | n >= 40 -> min n 120
    _ -> 80
