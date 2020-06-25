import std.stdio;

import arsd.game;

import arsd.png;

debug import std.stdio;

import arsd.ttf;

import t.game;

private static immutable ubyte[] fontFile;

private static immutable IndexedImage TileImage;

static immutable int[Tetrimino] tierList;

shared static this()
{
	import std.file : read;
	fontFile = (cast(ubyte[])read("font.ttf")).idup;
	TileImage = cast(immutable)(readPng("tile.png").getAsTrueColorImage().quantize());
	import std.exception : assumeUnique;
	auto tempList = [
		Tetrimino.T: 3,
		Tetrimino.L: 2,
		Tetrimino.S: 2,
		Tetrimino.I: 1,
		Tetrimino.O: 1,
		Tetrimino.S: 0,
		Tetrimino.Z: 0
	];
	tierList = tempList.assumeUnique;
}


final class Hatetris : GameHelperBase
{
	TetState state;
	alias state this;
	private Duration accumulated;
	private Duration delay;
	import std.datetime.stopwatch;
	private StopWatch lockDelay;
	StopWatch displayDelay;
	private TetriminoGenerator generator;
	private bool heldThisLock;
	bool lastWasRot;
	int score;
	private int _level = 1;
	int level()
	{
		return _level;
	}
	int level(int n)
	{
		import std.math : pow;
		enum hnsecsPerSecond = convert!("seconds", "hnsecs")(1);
		immutable numSecs = pow(0.8-_level*0.007,_level);
		delay = hnsecs(cast(int)(numSecs*hnsecsPerSecond));
		return _level = n;
	}
	private Tetrimino holding;
	private bool paused = false;
	private bool lost = false;
	this()
	{
		state.board = Grid!Tetrimino(10,40);
		state.parent = this;
		generator = new HatetrisGenerator(&state);
		nextPiece();
		delay = seconds(1);
		displayDelay.start();
	}
	private void softDrop()
	{
		if(pieceCanMove(Dir.S))
		{
			piecePos = piecePos + Dir.S;
			score++;
		}
	}
	private void leftShift()
	{
		if(pieceCanMove(Dir.W))
		{
			piecePos = piecePos + Dir.W;
			lastWasRot = false;
		}
	}
	private void rightShift()
	{
		if(pieceCanMove(Dir.E))
		{
			piecePos = piecePos + Dir.E;
			lastWasRot = false;
		}
	}
	private void rotate(bool counter = false)
	{
		import std.range : cycle;
		static immutable rotCycle = (cast(byte[])[0,1,2,3]).cycle();
		immutable oldRot = piece.rotation;
		if(counter)
		{
			piece.rotation = rotCycle[oldRot + 1];
		}
		else
		{
			piece.rotation = rotCycle[oldRot - 1];
		}
		bool canMove = false;
		foreach(pos;wallKickCoords(oldRot,piece.rotation))
		{
			if(pieceCanMove(pos))
			{
				canMove = true;
				piecePos = piecePos + pos;
				break;
			}
		}
		if(!canMove)
		{
			piece.rotation = oldRot;
		}
		else
		{
			lastWasRot = true;
			lockDelay.reset();
		}
	}
	private void nextPiece()
	{
		piece.pieceType = generator.next();
		piece.rotation = 0;
		piecePos = Point(4,21);
		if(!pieceCanMove(Point(0,0)))
		{
			lost = true;
		}
	}
	private void holdPiece()
	{
		if(!heldThisLock)
		{
			heldThisLock = true;
			if(holding != Tetrimino.None)
			{
				import std.algorithm.mutation : swap;
				swap(holding,piece.pieceType);
				if(!pieceCanMove(Point(0,0)))
				{
					foreach(dir;directions)
					{
						if(pieceCanMove(dir))
						{
							piecePos = piecePos + dir;
							break;
						}
					}
				}
			}
			else
			{
				holding = piece.pieceType;
				nextPiece();
			}
		}
	}
	bool combo;
	bool lastTSpin;
	size_t lastCleared;
	private void lockPiece()
	{
		if(!pieceCanMove(Dir.S))
		{
			state.lockPiece();
			heldThisLock = false;
			lockDelay.stop();
			lockDelay.reset();
			nextPiece();
		}
		else
		{
			lockDelay.reset();
		}
	}
	private bool checkControls()
	{
		bool didSomething = false;
		if(snes.justPressed(VirtualController.Button.Up)) {
			hardDrop();
			didSomething = true;
		}
		if(snes[VirtualController.Button.Down])
		{
			softDrop();
			didSomething = true;
		}
		if(snes.justPressed(VirtualController.Button.Left)) 
		{
			leftShift();
			didSomething = true;
		}
		if(snes.justPressed(VirtualController.Button.Right)) 
		{
			rightShift();
			didSomething = true;
		}
		if(snes.justPressed(VirtualController.Button.B)) 
		{
			rotate(false);
			didSomething = true;
		}
		if(snes.justPressed(VirtualController.Button.A)) 
		{
			rotate(true);
			didSomething = true;
		}
		if(snes.justPressed(VirtualController.Button.X) ||
		   snes.justPressed(VirtualController.Button.L) ||
		   snes.justPressed(VirtualController.Button.R))
		{
			holdPiece();
			didSomething = true;
		}
		return didSomething;
	}
	override bool update(Duration time)
	{
		if(!paused || lost) accumulated += time;
		bool shouldUpdate = checkControls();
		if(lockDelay.peek() > msecs(500))
		{
			lockPiece();
		}
		if(accumulated > delay)
		{
			if(!pieceCanMove(piecePos,Dir.S))
			{
				if(!lockDelay.running)
				{
					lockDelay.start();
					lockDelay.reset();
				}
			}
			else
			{
				piecePos = piecePos + Dir.S;
			}
			accumulated -= delay;
			shouldUpdate = true;
		}
		return shouldUpdate;
	}
	import std.traits : EnumMembers,Unqual;
	private static OpenGlTexture[2][EnumMembers!(Tetrimino).length] textures;
	static OpenGlLimitedFont!(OpenGlFontGLVersion.old) font;
	void drawTile(inout Tetrimino t,inout Point pos,bool ghost = false)
	{
		if(t != Tetrimino.None)
		{
			enum offset = Point(177,3-(16*20)); // supposed to have a slightly visible extra on top
			textures[cast(size_t)t][cast(size_t)ghost].draw(pos*16 + offset);
		}
	}
	void drawTileNoTransform(inout Tetrimino t,inout Point pos)
	{
		if(t != Tetrimino.None)
		{
			textures[cast(size_t)t][false].draw(pos);
		}
	}
	override void drawFrame()
	{
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_ACCUM_BUFFER_BIT);
		glLoadIdentity();
		foreach(idx,t;board)
		{
			drawTile(t,Point(cast(int)(idx%board.width),cast(int)(idx/board.width)));
		}
		immutable ghostPos = getCurHardDropPos();
		immutable relPoses = piece.relativePoses();
		foreach(pos;relPoses)
		{
			immutable realPos = ghostPos + pos;
			drawTile(piece.pieceType,realPos,true);
			drawTile(piece.pieceType,piecePos+pos);
		}
		if(generator.length)
		{
			foreach(i;0..generator.length)
			{
				immutable tile = PieceToDrop(generator.peek(i));
				if(tile.pieceType != Tetrimino.None)
				{
					foreach(pos;tile.relativePoses())
					{
						drawTileNoTransform(tile.pieceType,Point(360,26)+(Dir.S*(cast(int)i*48)+(pos*16)));
					}
				}
			}
		}
		if(holding)
		{
			foreach(pos;PieceToDrop(holding).relativePoses())
			{
				drawTileNoTransform(holding,Point(115,25)+pos*16);
			}
		}
		makeCachedPrimitive!(
		{
		import std.range : chunks;
		static immutable short[] playRectangle = [176,1,336,1,336,323,176,323];
		static immutable short[] queueRectangle = [340,10,340,334,410,334,410,10];
		static immutable short[] holdRectangle = [100,1,170,1,170,65,100,65];

		glColor3f(1.0,1.0,1.0);
		glBegin(GL_LINE_LOOP);
			foreach(chunk;playRectangle.chunks(2))
			{
				glVertex2i(chunk[0],chunk[1]);
			}
		glEnd();
		glBegin(GL_LINE_LOOP);
			foreach(chunk;queueRectangle.chunks(2))
			{
				glVertex2i(chunk[0],chunk[1]);
			}
		glEnd();
		glBegin(GL_LINE_LOOP);
			foreach(chunk;holdRectangle.chunks(2))
			{
				glVertex2i(chunk[0],chunk[1]);
			}
		glEnd();
		font.drawString(70,100,"Score: ");
		})();
		import std.conv : to;
		font.drawString(120,100,score.to!string);
		if(displayDelay.peek() < msecs(1500))
		{
			if(lastTSpin) makeCachedPrimitive!({ font.drawString(70,150,"T-spin"); })();
			final switch(lastCleared)
			{
				case 0:
					break;
				case 1:
					makeCachedPrimitive!({ font.drawString(70,160,"Single"); })();
					break;
				case 2:
					makeCachedPrimitive!({ font.drawString(70,160,"Double"); })();
					break;
				case 3:
					makeCachedPrimitive!({ font.drawString(70,160,"Triple"); })();
					break;
				case 4:
					makeCachedPrimitive!({ font.drawString(70,160,"[REDACTED]"); })();
					break;
			}
		}
		generator.draw();
	}
	override SimpleWindow getWindow()
	{
		auto window = create2dWindow("Tetris",512,512);
		Unqual!(typeof(TileImage)) tempTex;
		debug writeln("Loading textures.");
		static foreach(ghost;[false,true])
		{
			static foreach(t;EnumMembers!Tetrimino)
			{
				tempTex = TileImage.clone();
				foreach(ref col;tempTex.palette)
				{
					col = col.setSaturation(1);
					static if(t == Tetrimino.T)
					{
						col = col.setHue(300.0);
					}
					else static if(t == Tetrimino.L)
					{
						col = col.setHue(30.0);
					}
					else static if(t == Tetrimino.J)
					{
						col = col.setHue(240.0);
					}
					else static if(t == Tetrimino.I)
					{
						col = col.setHue(180.0);
					}
					else static if(t == Tetrimino.O)
					{
						col = col.setHue(60.0);
					}
					else static if(t == Tetrimino.Z)
					{
						col = col.setHue(0.0);
					}
					else static if(t == Tetrimino.S)
					{
						col = col.setHue(120.0);
					}
					col = col.darken(0.2);
					static if(ghost)
					{
						col.a = 128;
					}
				}
				textures[cast(size_t)t][cast(size_t)ghost] = new OpenGlTexture(tempTex.getAsTrueColorImage());
			}
		}
		debug writeln("Loaded textures.");
		font = new OpenGlLimitedFont!()(fontFile,16);
		return window;
	}
}

void main()
{
	runGame!(Hatetris)(60,60);
}
