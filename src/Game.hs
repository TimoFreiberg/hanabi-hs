{-# LANGUAGE OverloadedStrings #-}

module Game where

import Control.Lens
       (over, view, to, ix, traversed, mapped, at, non, set)
import qualified Data.List as List (delete)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Random.Shuffle (shuffleM)
import Types

colors :: [Color]
colors = [minBound .. maxBound]

numbers :: [Number]
numbers = [minBound .. maxBound]

occurrences :: Number -> Int
occurrences One = 3
occurrences Two = 2
occurrences Three = 2
occurrences Four = 2
occurrences Five = 1

handSize :: Int -> Int
handSize 2 = 5
handSize 3 = 5
handSize 4 = 4
handSize 5 = 4
handSize n = error ("the game does not support " ++ show n ++ " players!")

maximumFailures :: Int
maximumFailures = 3

sortedGame :: [Card]
sortedGame = concat (concat allCards)
  where
    numberCards col num = replicate (occurrences num) (Card col num)
    colorCards col = map (numberCards col) numbers
    allCards = map colorCards colors

dealCards :: Int -> IO ([[Card]], [Card])
dealCards playerCount = do
  cards <- shuffleM sortedGame
  let (hands', dk) = splitAt (playerCount * handSize playerCount) cards
  let hands = inGroupsOf (handSize playerCount) hands'
  return (hands, dk)

inGroupsOf :: Int -> [a] -> [[a]]
inGroupsOf _ [] = []
inGroupsOf n xs =
  let (as, bs) = splitAt n xs
  in as : inGroupsOf n bs

-- propNNumbers :: Int -> Number -> Color -> Bool
-- propNNumbers n num col = length ones == n
--   where
--     ones =
--         filter
--             (\(Card c n) ->
--                   c == col && n == num)
--             sortedGame
-- spec :: IO ()
-- spec =
--     hspec $
--     describe "the sorted game" $
--     do it "has three ones" $ property $ propNNumbers 3 One
--        it "has two twos" $ property $ propNNumbers 2 Two
--        it "has two threes" $ property $ propNNumbers 2 Three
--        it "has two fours" $ property $ propNNumbers 2 Four
--        it "has one five" $ property $ propNNumbers 1 Five
initState :: PlayerId -> [PlayerId] -> IO Game
initState startId ids = do
  (cards, dk) <- dealCards (length cleanIds)
  let hands = fmap createHand cards
  let players = Map.fromList (zip cleanIds hands)
  return (Game startId players dk Map.empty [] initialHints 0)
  where
    cleanIds = startId : List.delete startId ids

canPlayCard :: Card -> Game -> Bool
canPlayCard (Card col num1) game =
  case getStack col game of
    [] -> num1 == One
    Card _ num2:_ -> num1 `isSucc` num2

isFive :: Card -> Bool
isFive (Card _ Five) = True
isFive _ = False

tooManyFailures :: Game -> Bool
tooManyFailures game = view fuckups game >= maximumFailures

allStacksFilled :: Game -> Bool
allStacksFilled game =
  length stacks == length colors &&
  all (\stack -> length stack == length numbers) stacks
  where
    stacks = view (playedCards . to Map.elems) game

getStack :: Color -> Game -> [Card]
getStack col = view (playedCards . ix col)

removeFromHand :: Card -> Game -> Game
removeFromHand card game = over handOfActivePlayer (Map.delete card) game
  where
    handOfActivePlayer = playerHands . ix (view actingPlayer game)

putOnPlayedStack :: Card -> Game -> Game
putOnPlayedStack card =
  over (playedCards . at (view color card) . non []) (card :)

putOnDiscardedStack :: Card -> Game -> Game
putOnDiscardedStack card = over discardedCards (card :)

recordFailure :: Game -> Game
recordFailure = over fuckups (+ 1)

incrementHintCount :: Game -> Game
incrementHintCount = over hints (+ 1)

decrementHintCount :: Game -> Game
decrementHintCount = over hints (subtract 1)

giveHint :: Hint -> PlayerId -> Game -> Game
giveHint hint player =
  over (playerHands . at player . non Map.empty) (applyHint hint)

applyHint :: Hint -> Hand -> Hand
applyHint (ColorHint col1) = Map.mapWithKey (Set.insert . makeFact)
  where
    makeFact (Card col2 _)
      | col1 == col2 = IsColor col1
      | otherwise = Not (IsColor col1)
applyHint (NumberHint num1) = Map.mapWithKey (Set.insert . makeFact)
  where
    makeFact (Card _ num2)
      | num1 == num2 = IsNumber num1
      | otherwise = Not (IsNumber num1)

nextPlayer :: Game -> Game
nextPlayer game = set actingPlayer playerAfter game
  where
    oldPlayer = view actingPlayer game
    playerAfter =
      view
        (playerHands . to ((!! 1) . dropWhile (/= oldPlayer) . cycle . Map.keys))
        game

drawCard :: Game -> Game
drawCard game =
  over
    (playerHands . at (view actingPlayer game) . non Map.empty)
    (Map.insert card Set.empty)
    game
  where
    card = undefined

getScore :: Game -> Int
getScore =
  sum .
  view
    (playedCards .
     to (fmap (take 1)) .
     traversed . to (fmap (view number)) . to (fmap numToInt))

numToInt One = 1
numToInt Two = 2
numToInt Three = 3
numToInt Four = 4
numToInt Five = 5

exampleCards =
  [ Card Red One
  , Card Red Two
  , Card Red Three
  , Card Red Four
  , Card White One
  , Card White Two
  , Card Blue One
  , Card Blue Three
  , Card Blue Four
  , Card Blue Five
  ]

exampleGame =
  fmap
    (\g -> foldl (flip putOnPlayedStack) g exampleCards)
    (initState "1" ["2", "3"])
