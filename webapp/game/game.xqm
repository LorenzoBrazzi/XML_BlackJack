xquery version "3.0";

(: Nötige Module importieren:)
module namespace game = "bj/game";
import module namespace player = "bj/player" at "player.xqm";
import module namespace dealer = "bj/dealer" at "dealer.xqm";
import module namespace chip = "bj/chip" at "chip.xqm";
import module namespace card = "bj/card" at "card.xqm";

(: Hiermit generieren wir die IDs sowohl der Spiele als auch der Spieler :)
declare namespace uuid = "java:java.util.UUID";
declare namespace random = "http://basex.org/modules/random";
declare namespace update = "http://basex.org/modules/update";

declare variable $game:games := db:open("games")/games;
declare variable $game:d := game:shuffleDeck();

declare function game:getGame() {
    $game:games
};

(:Zum testen der Datenbank:)
declare function game:createEmptyGame(){
    let $id := xs:string(uuid:randomUUID())
    return (
        <game id="{$id}">
        </game>
    )
};

(: Spiel aus den Daten der Formulare instanzieren:)
declare function game:createGame($names as xs:string+, $balances as xs:integer+, $minBet as xs:integer,
        $maxBet as xs:integer) as element(game){
    let $gameId := xs:string(uuid:randomUUID())
    let $players := (for $i in (1 to fn:count($balances))
    return (
        player:createPlayer(xs:string(uuid:randomUUID()), card:emptyHand(), $minBet, $balances[$i],
                $names[$i], fn:false(), $i)
    ))
    return (
        <game>
            <id>{$gameId}</id>
            <maxBet>{$maxBet}</maxBet>
            <minBet>{$minBet}</minBet>
            <players>{$players}</players>
            <activePlayer>{$players[1]/id/text()}</activePlayer>
            <dealer>
                <currentHand></currentHand>
                <isInsurance>{fn:false()}</isInsurance>
            </dealer>
            {$game:d}
        </game>
    )
};

declare
%updating
function game:insertGame($g as element(game)){
    insert node $g as first into $game:games
};


declare
%updating
function game:deleteGame($gameID as xs:string){
    delete node $game:games/game[id = $gameID]
};

(:Nächsten Spieler lokalisieren und festlegen als Aktiver Spieler
  Falls letzter Spieler fertig ist, rufe evaluateRound() auf
:)
declare
%updating
function game:setActivePlayer($gameID as xs:string){
    let $oldPlayerID := $game:games/game[id = $gameID]/activePlayer
    let $oldPlayer := $game:games/game[id = $gameID]/players/player[id = $oldPlayerID]
    let $players := $game:games/game[id = $gameID]/players
    let $newPlayerID := $players/$oldPlayer/following::*[1]/id/text()
    return (
        if (fn:not(game:isRoundCompleted($gameID))) then (
            if (fn:empty($newPlayerID)) then (
                replace value of node $oldPlayerID with $players/player[1]/id/text()
            ) else (replace value of node $oldPlayerID with $newPlayerID))
        else (dealer:turnCard($gameID),
        game:evaluateRound($gameID))
    )

(: WIR MÜSSEN NOCH DEN FALL ABCHECNKEN WENN KEIN SPIELER MEHR DA IST ALSO WENN activePlayer = ""
    --> Wir haben doch die Position IDs mit Zahlen von 1 bis 5 gemacht, somit können wir einfach den Spieler dann
    aufrufen, der an Pos 1 sitzt:)
};

declare function game:getPlayerNames($gameID as xs:string){
    let $players := $game:games/game[id = $gameID]/players
    let $playerNames := (for $player in $players
    return (
        $player/name/text()
    )
    )
    return $playerNames
};


(: Shuffle Function:)
declare
%private
function game:shuffleDeck() as element(cards){
    let $cardSet := doc("./deck.xml")/cards/*
    let $deck := <cards>
        {$cardSet}
        {$cardSet}
        {$cardSet}
        {$cardSet}
        {$cardSet}
        {$cardSet}
    </cards>

    let $shuffled :=
        for $c in $deck/card
        order by random:integer(52)
        return $c

    return <cards>
        {$shuffled}
    </cards>
};

(:Public setter Function of shuffle():)
declare
%updating
function game:setShuffledDeck($gameID as xs:string){
    let $deck := $game:games/game[id = $gameID]/cards
    let $shuffled := game:shuffleDeck()

    return (
        delete node $deck,
        insert node $shuffled into $game:games/game[id = $gameID]
    )
};

(:Erhatle Deck für diverse andere Funktionen:)
declare function game:getDeck($gameID as xs:string) as element(cards){
    let $deck := $game:games/game[id = $gameID]/cards
    return $deck
};

(:Funktion für Spieler und Dealer um eine Karte zu ziehen und zugleich die gezogene Karte aus dem Deck Stack
zu entfernen:)
declare function game:drawCard($gameID as xs:string) as element(card){
    let $deck := game:getDeck($gameID)
    let $card := $deck/card[1]

    return $card
};

(:Nach ziehen einer Karte wird diese aus dem Stack entfernt, Controller muss diese hier bei jeder Draw funktion
extern aufrufen:)
declare
%updating
function game:popDeck($gameID as xs:string){
    let $deck := game:getDeck($gameID)
    return delete node $deck/card[1]
};

declare
%updating
function game:dealOutCards($gameID as xs:string){
    let $g := $game:games/game[id = $gameID]
    return (
        let $dealer := $g/dealer
        for $p in $g/players/player
        return (
            let $pos := xs:integer($p/position)
            return ( insert node $g/cards/card[($pos * 2) - 1] into $p/currentHand/cards,
            insert node $g/cards/card[($pos * 2)] into $p/currentHand/cards,
            delete node $g/cards/card[($pos * 2) - 1],
            delete node $g/cards/card[($pos * 2)],
            if ((xs:integer(fn:count($g/players))) = $pos) then (
                insert node $g/cards/card[11] into $dealer/currentHand,
                insert node $g/cards/card[12] into $dealer/currentHand,
                delete node $g/cards/card[11],
                delete node $g/cards/card[12]
            ) else ()
            )
        )
    )
};


declare function game:isRoundCompleted($gameID as xs:string) as xs:boolean{
    let $activeID := $game:games/game[id = $gameID]/activePlayer
    let $activePlayer := $game:games/game[id = $gameID]/players/player[id = $activeID]
    return (
        if ($activePlayer/position = 5)
        then (fn:true) else (fn:false)
    )
};

declare
%updating
function game:determineWinners($gameID as xs:string) {
    let $players := $game:games/game[id = $gameID]/players
    let $dealerCardsValue := dealer:calculateDealerValue($gameID)


    for $p in $players
    return (
        let $numberOfCards := fn:count($p/currentHand/card)
        let $playerCardValue := player:calculateCardValuePlayers($gameID, $p/id/text())
        return (
            if (($playerCardValue = 21) or ($numberOfCards = 2)) then (
                replace node $p/won with (
                    <won bj="true">{fn:true()}</won>
                )
            ) else if (($playerCardValue) > 21 or ($dealerCardsValue <= $playerCardValue))
            then ( replace value of node $p/won with fn:false())
            else (
                    replace value of node $p/won with fn:true()
                )
        )
    )
};

declare
%updating
function game:evaluateRound($gameID as xs:string) {
    let $players := $game:games/game[id = $gameID]/players
    let $insurancePossible := $game:games/game[id = $gameID]/dealer/isInsurance

    for $p in $players
    return (
        let $playerWon := $p/won
        return (if ($playerWon/@bj = "true") then (
            player:payoutBJ($gameID, $p/id/text())
        ) else if ($playerWon) then (
            player:payoutBalanceNormal($gameID, $p/id/text())
        ) else if (($insurancePossible) and ($p/insurance)) then (
            player:payoutInsurance($gameID, $p/id/text())
        ) else ()
        )
    )
};