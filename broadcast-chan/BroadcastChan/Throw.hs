{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE Safe #-}
-------------------------------------------------------------------------------
-- |
-- Module      :  BroadcastChan.Throw
-- Copyright   :  (C) 2014-2020 Merijn Verstraaten
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Merijn Verstraaten <merijn@inconsistent.nl>
-- Stability   :  experimental
-- Portability :  haha
--
-- This module is identical to "BroadcastChan", but with
-- @BroadcastChan.@'BroadcastChan.writeBChan' and
-- @BroadcastChan.@'BroadcastChan.readBChan' replaced with versions that throw
-- an exception, rather than returning results that the user has to inspect to
-- check for success.
-------------------------------------------------------------------------------
module BroadcastChan.Throw
    ( BChanError(..)
    , readBChan
    , writeBChan
    -- * Re-exports from "BroadcastChan"
    -- ** Datatypes
    , BroadcastChan
    , Direction(..)
    , In
    , Out
    -- ** Construction
    , newBroadcastChan
    , newBChanListener
    -- ** Basic Operations
    , closeBChan
    , isClosedBChan
    , getBChanContents
    -- ** Parallel processing
    , Action(..)
    , Handler(..)
    , parMapM_
    , parFoldMap
    , parFoldMapM
    -- ** Foldl combinators
    -- | Combinators for use with Tekmo's @foldl@ package.
    , foldBChan
    , foldBChanM
    ) where

import Control.Monad (when)
import Control.Monad.IO.Unlift (MonadIO(..))
import Control.Exception (Exception, throwIO)
import Data.Typeable (Typeable)

import BroadcastChan hiding (writeBChan, readBChan)
import qualified BroadcastChan as Internal

-- | Exception type for 'BroadcastChan' operations.
data BChanError
    = WriteFailed   -- ^ Attempted to write to closed 'BroadcastChan'
    | ReadFailed    -- ^ Attempted to read from an empty closed 'BroadcastChan'
    deriving (Eq, Read, Show, Typeable)

instance Exception BChanError

-- | Like 'Internal.readBChan', but throws a 'ReadFailed' exception when
-- reading from a closed and empty 'BroadcastChan'.
readBChan :: MonadIO m => BroadcastChan Out a -> m a
readBChan ch = do
    result <- Internal.readBChan ch
    case result of
        Nothing -> liftIO $ throwIO ReadFailed
        Just x -> return x
{-# INLINE readBChan #-}

-- | Like 'Internal.writeBChan', but throws a 'WriteFailed' exception when
-- writing to closed 'BroadcastChan'.
writeBChan :: MonadIO m => BroadcastChan In a -> a -> m ()
writeBChan ch val = do
    success <- Internal.writeBChan ch val
    when (not success) . liftIO $ throwIO WriteFailed
{-# INLINE writeBChan #-}
