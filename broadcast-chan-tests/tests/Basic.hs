import Control.Foldl (Fold, FoldM)
import qualified Control.Foldl as Foldl
import Control.Monad (forM_)
import Control.Monad.Loops (unfoldM)
import Data.Maybe (isNothing)
import System.IO (Handle, hPrint)
import System.Random (getStdGen, randomIO, randoms)
import System.Timeout (timeout)

import BroadcastChan
import BroadcastChan.Test
import BroadcastChan.Throw (BChanError(..))
import qualified BroadcastChan.Throw as Throw

shouldn'tBlock :: IO a -> IO a
shouldn'tBlock act = do
    result <- timeout 2000000 act
    case result of
        Nothing -> assertFailure "Shouldn't block!"
        Just a -> return a

checkedWrite :: BroadcastChan In a -> a -> IO ()
checkedWrite chan val = writeBChan chan val @? "Write shouldn't fail"

randomList :: Int -> IO [Int]
randomList n = take n . randoms <$> getStdGen

readTests :: TestTree
readTests = testGroup "read tests"
    [ readNonEmpty
    , readNonEmptyThrow
    , readEmptyClosed
    , readEmptyClosedThrow
    ]
  where
    readNonEmpty :: TestTree
    readNonEmpty = testCase "read non-empty" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        val <- randomIO :: IO Int

        writeBChan inChan val
        result <- shouldn'tBlock $ readBChan outChan
        assertEqual "Read should match write" (Just val) result

    readNonEmptyThrow :: TestTree
    readNonEmptyThrow = testCase "read non-empty (throw)" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        val <- randomIO :: IO Int

        writeBChan inChan val
        result <- shouldn'tBlock $ Throw.readBChan outChan
        assertEqual "Read should match write" val result

    readEmptyClosed :: TestTree
    readEmptyClosed = testCase "read empty closed" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        closeBChan inChan
        isNothing <$> shouldn'tBlock (readBChan outChan) @? "Read should fail"

    readEmptyClosedThrow :: TestTree
    readEmptyClosedThrow = testCase "read empty closed (throw)" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        closeBChan inChan
        expect ReadFailed . shouldn'tBlock $ Throw.readBChan outChan

writeTests :: TestTree
writeTests = testGroup "write tests"
    [ writeClosed
    , writeClosedThrow
    , writeBeforeListener "write before listener" $ checkedWrite
    , writeBeforeListener "write before listener (throw)" $ Throw.writeBChan
    , writeBroadCast "write broadcast" $ checkedWrite
    , writeBroadCast "write broadcast (throw)" $ Throw.writeBChan
    ]
  where
    writeClosed :: TestTree
    writeClosed = testCase "write closed" $ do
        chan <- newBroadcastChan
        closeBChan chan
        not <$> writeBChan chan () @? "Write should fail"

    writeClosedThrow :: TestTree
    writeClosedThrow = testCase "write closed (throw)" $ do
        chan <- newBroadcastChan
        closeBChan chan
        expect WriteFailed $ Throw.writeBChan chan ()

    writeBeforeListener
        :: String -> (BroadcastChan In Int -> Int -> IO ()) -> TestTree
    writeBeforeListener name write = testCase name $ do
        inChan <- newBroadcastChan
        forM_ [1..10] $ write inChan
        closeBChan inChan
        outChan <- newBChanListener inChan
        isNothing <$> readBChan outChan @? "Read should fail"

    writeBroadCast
        :: String -> (BroadcastChan In Int -> Int -> IO ()) -> TestTree
    writeBroadCast name write = testCase name $ do
        inChan <- newBroadcastChan
        outChan1 <- newBChanListener inChan
        outChan2 <- newBChanListener inChan
        inputs <- randomList 10

        forM_ inputs $ write inChan
        closeBChan inChan
        result1 <- unfoldM $ readBChan outChan1
        result2 <- unfoldM $ readBChan outChan2
        assertEqual "Result should equal input" inputs result1
        assertEqual "Results should be equal" result1 result2

closedTests :: TestTree
closedTests = testGroup "closed tests"
    [ noBlockUnclosedIn
    , noBlockClosedIn
    , noBlockUnclosedOut
    , noBlockClosedOut
    , noBlockClosedEmptyOut
    ]
  where
    noBlockUnclosedIn :: TestTree
    noBlockUnclosedIn = testCase "no block unclosed in" $ do
        chan <- newBroadcastChan
        not <$> shouldn'tBlock (isClosedBChan chan) @? "Shouldn't be closed"

    noBlockClosedIn :: TestTree
    noBlockClosedIn = testCase "no block closed in" $ do
        chan <- newBroadcastChan
        closeBChan chan
        shouldn'tBlock (isClosedBChan chan) @? "Should be closed"

    noBlockUnclosedOut :: TestTree
    noBlockUnclosedOut = testCase "no block unclosed out" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        not <$> shouldn'tBlock (isClosedBChan outChan) @? "Shouldn't be closed"

    noBlockClosedOut :: TestTree
    noBlockClosedOut = testCase "no block closed out" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        Throw.writeBChan inChan ()
        closeBChan inChan
        not <$> shouldn'tBlock (isClosedBChan outChan) @? "Shouldn't be closed"

    noBlockClosedEmptyOut :: TestTree
    noBlockClosedEmptyOut = testCase "no block closed empty out" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        closeBChan inChan
        shouldn'tBlock (isClosedBChan outChan) @? "Should be closed"

chanContentsTests :: TestTree
chanContentsTests = testGroup "getBChanContents"
    [ noBlockOnEmptyIn
    , noBlockOnEmptyOut
    , noBlockOnFilledIn
    , noBlockOnFilledOut
    , checkConcurrencyOut
    ]
  where
    noBlockOnEmptyIn :: TestTree
    noBlockOnEmptyIn = testCase "no block on empty in" $ do
        chan <- newBroadcastChan
        results <- shouldn'tBlock $ getBChanContents chan
        closeBChan chan
        shouldn'tBlock $ assertBool "Should be empty list!" (null results)

    noBlockOnEmptyOut :: TestTree
    noBlockOnEmptyOut = testCase "no block on empty out" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        results <- shouldn'tBlock $ getBChanContents outChan
        closeBChan inChan
        shouldn'tBlock $ assertBool "Should be empty list!" (null results)

    noBlockOnFilledIn :: TestTree
    noBlockOnFilledIn = testCase "no block on filled in" $ do
        inChan <- newBroadcastChan
        throwawayInputs <- randomList 10
        forM_ throwawayInputs $ Throw.writeBChan inChan
        results <- shouldn'tBlock $ getBChanContents inChan
        inputs <- randomList 10
        forM_ inputs $ Throw.writeBChan inChan
        closeBChan inChan
        assertEqual "Should be only inputs after action" inputs results

    noBlockOnFilledOut :: TestTree
    noBlockOnFilledOut = testCase "no block on filled out" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        inputsBefore <- randomList 10
        forM_ inputsBefore $ Throw.writeBChan inChan
        results <- shouldn'tBlock $ getBChanContents outChan
        inputsAfter <- randomList 10
        forM_ inputsAfter $ Throw.writeBChan inChan
        closeBChan inChan
        let allInputs = inputsBefore ++ inputsAfter
        assertEqual "Should be both inputs" allInputs results

    checkConcurrencyOut :: TestTree
    checkConcurrencyOut = testCase "interleaved with readBChan" $ do
        inChan <- newBroadcastChan
        outChan <- newBChanListener inChan
        inputs <- randomList 10
        forM_ inputs $ Throw.writeBChan inChan
        closeBChan inChan
        contents <- getBChanContents outChan
        forM_ contents $ \val -> do
            result <- readBChan outChan
            case result of
                Nothing -> assertFailure "Element missing!"
                Just v -> assertEqual "Should be equal" val v

foldlTests :: TestTree
foldlTests = testGroup "foldl tests"
    [ foldBChanIn
    , foldBChanOut
    , foldBChanMIn
    , foldBChanMOut
    ]
  where
    pureFold :: Fold a b -> BroadcastChan d a -> IO (IO b)
    pureFold = Foldl.purely foldBChan

    printList :: Show a => Handle -> FoldM IO a [a]
    printList hnd = Foldl.premapM doPrint $ Foldl.generalize Foldl.list
      where
        doPrint val = val <$ hPrint hnd val

    impureFold :: FoldM IO a b -> BroadcastChan d a -> IO (IO b)
    impureFold = Foldl.impurely foldBChanM

    foldBChanIn :: TestTree
    foldBChanIn = testCase "foldBChan in" $ do
        inChan <- newBroadcastChan
        inputsBefore <- randomList 10
        forM_ inputsBefore $ Throw.writeBChan inChan
        foldList <- shouldn'tBlock $ pureFold Foldl.list inChan

        inputsAfter <- randomList 10
        forM_ inputsAfter $ Throw.writeBChan inChan
        closeBChan inChan
        (inputsAfter==) <$> shouldn'tBlock foldList @? "Lists should be equal"

    foldBChanOut :: TestTree
    foldBChanOut = testCase "foldBChan out" $ do
        inChan <- newBroadcastChan
        inputsBefore <- randomList 10
        forM_ inputsBefore $ Throw.writeBChan inChan
        outChan <- newBChanListener inChan
        inputsBetween <- randomList 10
        forM_ inputsBetween $ Throw.writeBChan inChan

        foldList <- shouldn'tBlock $ pureFold Foldl.list outChan

        inputsAfter <- randomList 10
        forM_ inputsAfter $ Throw.writeBChan inChan
        closeBChan inChan

        let expected = inputsBetween ++ inputsAfter
        (expected==) <$> shouldn'tBlock foldList @? "Lists should be equal"

    foldBChanMIn :: TestTree
    foldBChanMIn = testCase "foldBChanM in" $ do
        inChan <- newBroadcastChan
        inputsBefore <- randomList 10
        forM_ inputsBefore $ Throw.writeBChan inChan
        inputsAfter <- randomList 10

        control <- withLoggedOutput "foldBChanControl.out" $ \hnd -> do
            Foldl.foldM (printList hnd) inputsAfter

        validation <- withLoggedOutput "foldBChanM.out" $ \hnd -> do
            foldPrintList <- shouldn'tBlock $ impureFold (printList hnd) inChan
            forM_ inputsAfter $ Throw.writeBChan inChan
            closeBChan inChan
            foldPrintList

        assertEqual "Results and output should be equal" control validation

    foldBChanMOut :: TestTree
    foldBChanMOut = testCase "foldBChanM out" $ do
        inChan <- newBroadcastChan
        inputsBefore <- randomList 10
        forM_ inputsBefore $ Throw.writeBChan inChan
        outChan <- newBChanListener inChan
        inputsBetween <- randomList 10
        forM_ inputsBetween $ Throw.writeBChan inChan
        inputsAfter <- randomList 10
        let expected = inputsBetween ++ inputsAfter

        control <- withLoggedOutput "foldBChanControl.out" $ \hnd -> do
            Foldl.foldM (printList hnd) expected

        validation <- withLoggedOutput "foldBChanM.out" $ \hnd -> do
            foldPrintList <- shouldn'tBlock $
                impureFold (printList hnd) outChan

            forM_ inputsAfter $ Throw.writeBChan inChan
            closeBChan inChan
            foldPrintList

        assertEqual "Results and output should be equal" control validation

main :: IO ()
main = runTests "basic"
  [ readTests
  , writeTests
  , closedTests
  , chanContentsTests
  , foldlTests
  ]
