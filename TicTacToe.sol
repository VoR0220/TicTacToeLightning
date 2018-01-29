pragma solidity ^0.4.19;

contract TicTacToe {
    
    address xs;
    address os;
    address challenger;
    address winner;
    
    modifier onlyPlayers() {
        require(msg.sender == xs || msg.sender == os);
        _;
    }
    
    // fallback function as our main payment mechanism. 
    // This allows the challenger to up the ante until someone will play by effectively allowing only a doubling of the balance
    // once the challangee deposits the funds the challenge is accepted and the game begins off chain
    function() public payable {
        require(msg.value == this.balance && msg.sender == xs || msg.sender == os);
    }
    
    // pick an opponent and declare whether you prefer xs or os
    // xs go first
    function TicTacToe(address opponent, bool deployerPlayingXs) public payable {
        // map out possible winning outcomes, set the users, use msg.sender for user and note the required deposit
        xs = deployerPlayingXs ? msg.sender : opponent;
        os = deployerPlayingXs ? opponent : msg.sender;
        challenger = msg.sender;
    }
    
    enum Squares {
        TopLeft, TopCenter, TopRight,
        MidLeft, MidCenter, MidRight,
        BottomLeft, BottomCenter, BottomRight
    }
    
    struct Move {
        uint8 order;
        address takenBy;
    }
    
    mapping(uint8=>Move) squaresHeld;
    
    // each move is defined by a signature where the signature array has to be alternating between players
    // A final signature is required to prove that somebody signed these signatures in order (nonces and all)
    // params:
    // _move: array of moves as denoted by their uint8 (which corresponds to their enum format in Squares above)
    // nonce: sequential nonces that should go from 0-9 (depending on number of moves)
    // hashes: hash of the message that is _move + the nonce
    // v, s, r: Read on ecrecover. These are the pieces of the signature that should correspond to the indexed hash
    // declaredWin: a function that will be used to determine how somebody won (this is cheaper than trying all the ways and helps narrow this down)
    function submitMoves(uint8[] _move, uint8[] nonce, bytes32[] hashes, uint8[] v, bytes32[] s, bytes32[] r, function(address) external view returns(bool) declaredWin) public onlyPlayers {
        // require exact number of signatures
        require(_move.length == nonce.length && nonce.length == hashes.length && hashes.length == v.length && v.length == s.length && s.length == r.length);
        uint moves = _move.length - 1;
        // minimum number of plays to win, therefore we require a certain amount of signatures of each move. There's also, obviously, a maximum amount of plays to win.
        // this will help us clamp down on falsey games. 
        require(moves >= 4 && moves < 9);
        
        // this is to compare our last signature to make sure that it's the one we are looking for.
        bytes32[] memory toHash;
        // alternate signatures and see who signed off on what move. Punish repeat moves.
        // maybe best to do this as a double celled array for simplicity's sake
        for (uint8 i = 0; i < moves; i++) {
            // require that the nonce uses sequential ordering
            require(nonce[i] == i); 
            // require that the move/nonce hash is equivalent to the hashes signed off on
            require(keccak256(_move[i], nonce[i]) == hashes[i]);
            // require that the move has not already been taken by one of the players
            require(squaresHeld[_move[i]].takenBy == 0x0);
            address recoveredAddr = ecrecover(hashes[i], v[i], s[i], r[i]);
            if (i % 2 == 0) {
                require(xs == recoveredAddr);
            } else {
                require(os == recoveredAddr);
            }
            squaresHeld[_move[i]] = Move(i, recoveredAddr);
            toHash[i] = keccak256(_move[i], nonce[i], hashes[i], v[i], s[i], r[i]);
        }
        bytes32 proofOfWinning = keccak256(toHash);
        require(proofOfWinning == hashes[_move.length]);
        require(declaredWin(msg.sender));
    }
    
    function declareWinThroughVerticals(address winner) external returns (bool) {
        bool leftBar = squaresHeld[uint8(Squares.TopLeft)].takenBy == winner && squaresHeld[uint8(Squares.MidLeft)].takenBy == winner && squaresHeld[uint8(Squares.BottomLeft)].takenBy == winner;
        bool middleBar = squaresHeld[uint8(Squares.TopCenter)].takenBy == winner && squaresHeld[uint8(Squares.MidCenter)].takenBy == winner && squaresHeld[uint8(Squares.BottomCenter)].takenBy == winner;
        bool rightBar = squaresHeld[uint8(Squares.TopRight)].takenBy == winner && squaresHeld[uint8(Squares.MidRight)].takenBy == winner && squaresHeld[uint8(Squares.BottomRight)].takenBy == winner;
        return leftBar || middleBar || rightBar;
    }
    
    function declareWinThroughHorizontals(address winner) external returns (bool) {
        bool topBar = squaresHeld[uint8(Squares.TopLeft)].takenBy == winner && squaresHeld[uint8(Squares.TopCenter)].takenBy == winner && squaresHeld[uint8(Squares.TopRight)].takenBy == winner;
        bool middleBar = squaresHeld[uint8(Squares.MidLeft)].takenBy == winner && squaresHeld[uint8(Squares.MidCenter)].takenBy == winner && squaresHeld[uint8(Squares.MidRight)].takenBy == winner;
        bool bottomBar = squaresHeld[uint8(Squares.BottomLeft)].takenBy == winner && squaresHeld[uint8(Squares.BottomCenter)].takenBy == winner && squaresHeld[uint8(Squares.BottomRight)].takenBy == winner;
        return topBar || middleBar || bottomBar;
    }
    
    // I cleaned this up because there was repeat usages and I figured this might help it gas wise
    function declareWinThroughDiagonals(address winner) external returns (bool) {
        address midCenter = squaresHeld[uint8(Squares.MidCenter)].takenBy;
        address topLeft = squaresHeld[uint8(Squares.TopLeft)].takenBy;
        address bottomRight = squaresHeld[uint8(Squares.BottomRight)].takenBy;
        address bottomLeft = squaresHeld[uint8(Squares.BottomLeft)].takenBy;
        address topRight = squaresHeld[uint8(Squares.TopRight)].takenBy;
        bool downwardSlope = topLeft == winner && midCenter == winner && bottomRight == winner;
        bool upwardSlope = bottomLeft == winner && midCenter == winner && topRight == winner;
        return downwardSlope || upwardSlope;
    }
    
    function declareWinThrough4Corners(address winner) external returns (bool) {
        return squaresHeld[uint8(Squares.TopLeft)].takenBy == winner && squaresHeld[uint8(Squares.BottomLeft)].takenBy == winner && squaresHeld[uint8(Squares.TopRight)].takenBy == winner && squaresHeld[uint8(Squares.BottomRight)].takenBy == winner;
    }
    
    // because we're good gamblers, lets make this game fun and just make it up the ante if there's a cat's game. 
    function declareCatsGame(address caller) external returns (bool) {
        //verify first that it actually is a cats game and that both cannot win. This also enables good sportsmanship if someone wants to implement a "mercy" option.
        require(caller == xs || caller == os);
        address opponent = caller == xs ? os : xs;
        bool containsWins = this.declareWinThrough4Corners(opponent) || this.declareWinThroughDiagonals(opponent) || this.declareWinThroughHorizontals(opponent) || this.declareWinThroughVerticals(opponent) 
            || this.declareWinThrough4Corners(caller) || this.declareWinThroughDiagonals(caller) || this.declareWinThroughHorizontals(caller) || this.declareWinThroughVerticals(caller);
        
        return !containsWins;
    }
}
