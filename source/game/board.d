module t.game.board;

import arsd.game;

enum Tetrimino : byte
{
	None,
	T,
	L,
	J,
	I,
	O,
	Z,
	S
}

static immutable tetriminosAsList = [
		Tetrimino.S,
		Tetrimino.Z,
		Tetrimino.O,
		Tetrimino.I,
		Tetrimino.L,
		Tetrimino.J,
		Tetrimino.T
];

package Point[4] rotatePairsImpl(
	immutable float x1, immutable float y1,
	immutable float x2, immutable float y2,
	immutable float x3, immutable float y3,
	immutable float x4, immutable float y4,
	immutable float originX,immutable float originY,
	immutable int rot)
{
	import std.math : PI_2;
	immutable theta = PI_2 * rot;
	Point[4] ret;
	float x;
	float y;
	static foreach(i;[1,2,3,4])
	{
		import std.math : round;
		import std.conv : to;
		rotateAboutPoint(theta,originX,originY,mixin("x"~i.to!string),mixin("y"~i.to!string),x,y);
		ret[i-1] = Point(cast(int)round(x),cast(int)round(y));
	}
	return ret;
}

immutable(Point[5]) wallKickCoordsImpl(int from, int to)
{
	if(from == 1) return [Point(0,0),Point(1,0),Point(1,-1),Point(0,2),Point(1,2)];
	else if(from == 3) return [Point(0,0),Point(-1,0),Point(-1,-1),Point(0,2),Point(-1,2)];
	else if(to == 1) return [Point(0,0),Point(-1,0),Point(-1,1),Point(0,-2),Point(-1,-2)];
	else if(to == 3) return [Point(0,0),Point(1,0),Point(1,1),Point(0,-2),Point(1,-2)];
	assert(0,"Missed one lol");
}

import std.functional : memoize;

alias rotatePairs = memoize!rotatePairsImpl;

alias wallKickCoords = memoize!wallKickCoordsImpl;

struct PieceToDrop
{
	Tetrimino pieceType;
	byte rotation;
	Point[4] relativePoses() inout
	{
		import std.range : cycle;
		static immutable rotations = [0,1,2,3].cycle;
		immutable rotation = rotations[rotation];
		scope(failure)
		{
			import core.runtime : defaultTraceHandler;
			debug
			{
                import std.stdio;
				auto trace = defaultTraceHandler(null);
				foreach (line; trace)
				{
					printf("%.*s\n", cast(int)line.length, line.ptr);
				}
			}
		}
		final switch(pieceType)
		{
			case Tetrimino.T:
				return rotatePairs(
						0.0,0.0,
						-1.0,0.0,
						0.0,-1.0,
						1.0,0.0
					,
					0.0,0.0,
					rotation);
			case Tetrimino.L:
				return rotatePairs(
					
						0.0,0.0,
						-1.0,0.0,
						1.0,0.0,
						1.0,-1.0
					,
					0.0,0.0,
					rotation);
			case Tetrimino.J:
				return rotatePairs(
					
						0.0,0.0,
						-1.0,0.0,
						1.0,0.0,
						-1.0,-1.0
					,
					0.0,0.0,
					rotation);
			case Tetrimino.I:
				return rotatePairs(
					
						-1.0,0.0,
						0.0,0.0,
						1.0,0.0,
						2.0,0.0
					,
					0.5,0.5,
					rotation);

			case Tetrimino.O:
				return [Point(0,0),Point(0,1),Point(1,0),Point(1,1)];
			case Tetrimino.Z:
				return rotatePairs(
					
						0.0,0.0,
						1.0,0.0,
						0.0,-1.0,
						-1.0,-1.0
					,
					0.0,0.0,
					rotation);
			case Tetrimino.S:
				return rotatePairs(
					
						0.0,0.0,
						-1.0,0.0,
						0.0,-1.0,
						1.0,-1.0
					,
					0.0,0.0,
					rotation);
			case Tetrimino.None:
				assert(0,"Impossible!");
		}
	}
}

import t.game.generators;

struct TetState
{
    import app : Hatetris;
	import std.typecons : Nullable;
	Grid!Tetrimino board;
	PieceToDrop piece;
	Point piecePos;
	Nullable!Hatetris parent;
	TetState copy()
	{
		TetState n;
		n.board = Grid!Tetrimino(board[].dup,Size(board.width,board.height));
		n.piece = piece;
		n.piecePos = piecePos;
		return n;
	}
	bool pieceCanMove(Point givenPos,Point dir = Dir.S)
	{
		immutable poses = piece.relativePoses;
		foreach(pos;poses)
		{
			immutable realPos = pos + givenPos + dir;
			if(realPos !in board)
			{
				return false;
			}
			if(board[realPos] != Tetrimino.None)
			{
				return false;
			}
		}
		return true;
	}
	bool pieceCanMove(Point dir)
	{
		return pieceCanMove(piecePos,dir);
	}
	Point getCurHardDropPos()
	{
		Point fakePos = piecePos;
		while(pieceCanMove(fakePos,Dir.S))
		{
			fakePos = fakePos + Dir.S;
		}
		return fakePos;
	}
	int towerHeight()
	{
		import std.algorithm.comparison : max;
		int maxHeight = 0;
		foreach(y;0..board.height)
		{
			foreach(x;0..board.width)
			{
				if(board[x,y] != Tetrimino.None) maxHeight = max(board.height-y,maxHeight);
			}
		}
		return maxHeight;
	}
	private void fall(size_t height)
	{
		for(size_t y=height;y>0;y--)
		{
			import std.algorithm.mutation : swap;
			foreach(size_t x;0..board.width)
			{
				swap(board[cast(int)x,cast(int)y],board[cast(int)x,cast(int)y-1]);
			}
		}
	}
	void clearLines(bool tSpin)
	{
		size_t[] cleared;
		cleared.reserve(4);
		foreach(y;0..board.height)
		{
			bool thisCleared = true;
			foreach(x;0..board.width)
			{
				if(board[x,y] == Tetrimino.None)
				{
					thisCleared = false;
					break;
				}
			}
			if(thisCleared) cleared ~= y;
		}
		if(cleared.length)
		{
			import std.algorithm.sorting : sort;
			foreach(y;cleared.sort)
			{
				foreach(x;0..board.width)
				{
					board[cast(int)x,cast(int)y] = Tetrimino.None;
				}
				fall(y);
			}
			if(!parent.isNull)
			{
				auto p = parent.get();
				tSpin = tSpin && p.lastWasRot;
				if(p.combo)
				{
					p.score += cleared.length*p.level+50*p.level;
				}
				immutable backToBackBonus = (p.lastTSpin && tSpin) ? 1.5 : 1.0;
				final switch(cleared.length)
				{
					case 1:
						p.score += cast(int)(100*p.level*(tSpin ? 8 : 1)*backToBackBonus);
						break;
					case 2:
						p.score += cast(int)(300*p.level*(tSpin ? 6 : 1)*backToBackBonus);
						break;
					case 3:
						p.score += cast(int)(500*p.level*(tSpin ? 3.2 : 1)*backToBackBonus);
						break;
					case 4:
						p.score += 800;
						if(p.lastCleared == 4) p.score += 400;
				}
				if(p.lastTSpin != tSpin || p.lastCleared != cleared.length)
				{
					p.displayDelay.reset();
				}
				p.combo = true;
				p.lastTSpin = tSpin;
				p.lastCleared = cast(int)(cleared.length);
			}
		}
		else
		{
			if(!parent.isNull)
			{
				auto p = parent.get();
				if(tSpin && p.lastWasRot)
				{
					p.lastTSpin = true;
					p.displayDelay.reset();
				}
				p.combo = false;
				p.lastCleared = 0;
			}
		}
	}
	void lockPiece()
	{
		foreach(pos;piece.relativePoses())
		{
			board[pos + piecePos] = piece.pieceType;
		}
		bool tSpin = false;
		if(piece.pieceType == Tetrimino.T)
		{
			import std.algorithm.setops : cartesianProduct;
			static immutable corners = [-1,1];
			int cornersFound = 0;
			foreach(pair;cartesianProduct(corners,corners))
			{
				immutable cornerPos = Point(pair[0],pair[1]) + piecePos;
				if((cornerPos in board) && board[cornerPos] != Tetrimino.None) cornersFound++;
				if(cornersFound > 2)
				{
					tSpin = true;
					break;
				}
			}
		}
		clearLines(tSpin);
	}
	void hardDrop()
	{
		auto oldPos = piecePos;
		piecePos = getCurHardDropPos;
		if(!parent.isNull)
		{
			parent.get.score += (piecePos - oldPos).y*2;
		}
	}
	void playOptimally()
	{
		int bestPlayScore = int.max;
		struct Play
		{
			int playX = -1;
			byte playRot = -1;
			bool valid()
			{
				return playX > -1 && playRot > -1;
			}
		}
		Play bestPlay;
		foreach(x;0..board.width+4)
		{
			foreach(byte rot;0..4)
			{
                auto newState = copy();
				newState.piecePos = Point(x,21);
				newState.piece.rotation = cast(byte)rot;
				if(newState.pieceCanMove(Point(0,0)))
				{
                    newState.hardDrop();
                    newState.lockPiece();
                    import std.stdio : writeln;
                    if(newState.towerHeight < bestPlayScore)
                    {
                        bestPlayScore = newState.towerHeight;
                        bestPlay.playX = x;
                        bestPlay.playRot = rot;
                    }
				}
			}
		}
		if(bestPlay.valid)
		{
            piecePos = Point(bestPlay.playX,21);
			piece.rotation = bestPlay.playRot;
			hardDrop();
            lockPiece();
		}
	}
	int opCmp(TetState b) {
		immutable cachedScore = towerHeight();
		immutable otherScore = b.towerHeight();
		if(cachedScore > otherScore) return -1; 
		else if(cachedScore < otherScore) return 1;
		return 0;
	}
}