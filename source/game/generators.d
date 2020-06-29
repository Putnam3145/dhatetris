module t.game.generators;

import t.game.board : Tetrimino, tetriminosAsList, TetState;

debug import std.stdio;

interface TetriminoGenerator
{
	Tetrimino front();
	void popFront();
	final Tetrimino next()
	{
		scope(exit) popFront();
		return front();
	}
	final bool empty() { return false; }
	Tetrimino peek(size_t n) in { assert(n < 14); }
	size_t length();
    void draw();
}

class StandardsCompliantGenerator : TetriminoGenerator
{
	import std.random : randomCover;
	import std.range.primitives;
	import std.range : cycle;
	private Tetrimino[14] _underlying;
	private typeof(_underlying.cycle) range;
	private size_t idx;
	this()
	{
		import std.array;
		range = _underlying.cycle();
		_underlying[0..7] = tetriminosAsList.randomCover.array;
		_underlying[7..14] = tetriminosAsList.randomCover.array;
	}
	Tetrimino front()
	{
		return range.front;
	}
	void popFront()
	{
		range.popFront();
		idx++;
		if(idx > 6)
		{
			auto newBag = tetriminosAsList.randomCover;
			foreach(ref item;range[idx..idx+7])
			{
				item = newBag.front();
				newBag.popFront();
			}
			idx = 0;
		}
	}
	size_t length()
	{
		return 7;
	}
	Tetrimino peek(size_t n)
	{
		return range[n];
	}
    void draw() {}
}

private pure @safe @nogc int tier(Tetrimino t)
{
    final switch(t)
    {
        case Tetrimino.T:
            return 4;
        case Tetrimino.J:
        case Tetrimino.L:
            return 3;
        case Tetrimino.I:
        case Tetrimino.O:
            return 2;
        case Tetrimino.S:
        case Tetrimino.Z:
            return 1;
        case Tetrimino.None:
            return 0;
    }
}

class HatetrisGenerator : TetriminoGenerator
{
	import std.parallelism : task, taskPool;
	import core.atomic;
	private TetState* baseState;
    private shared bool done = false;
    private shared ulong depth = 0;
	private shared Tetrimino nextCached = Tetrimino.S;
	private typeof(task(&generateNext)) working;
	this(TetState* s)
	{
		baseState = s;
        working = cast(typeof(working))task(&generateNext);
        taskPool.put(working);
	}
    class StateSeries
    {
        private StateSeries[Tetrimino] descendents;
        private TetState state;
        private Tetrimino dropped;
        private int worst = int.max;
        private int depth = 0;
        int expectedScore()
        {
            return worst;
        }
        this(TetState s,Tetrimino p)
        {
            state = s;
            dropped = p;
            worst = state.towerHeight;
        }
        void append(TetState state,Tetrimino piece)
        {
            import std.algorithm.comparison : max;
            descendents[piece] = new StateSeries(state,piece);
            worst = max(descendents[piece].worst,worst);
        }
        import std.datetime.stopwatch;
        void prune(ref StopWatch sw)
        {
            import core.time : msecs;
            if(descendents.length > 1)
            {
                if(sw.peek() > msecs(1000))
                {
                    Tetrimino[] toCheck;
                    toCheck.reserve(7);
                    foreach(key,value;descendents)
                    {
                        if(value.worst <= worst)
                        {
                            toCheck ~= key;
                        }
                        else
                        {
                            value.prune(sw);
                        }
                    }
                    if(toCheck.length)
                    {
                        import std.algorithm.searching : minElement;
                        immutable minTier = minElement!((a) => a.tier)(toCheck).tier;
                        foreach(k;toCheck)
                        {
                            if(k.tier > minTier)
                            {
                                descendents.remove(k);
                            }
                            else
                            {
                                descendents[k].prune(sw);
                            }
                        }
                    }
                }
                else
                {
                    foreach(key,value;descendents)
                    {
                        if(value.worst < worst)
                        {
                            descendents.remove(key);
                        }
                        else
                        {
                            value.prune(sw);
                        }
                    }
                }
            }
        }
        void doDescent(ref shared(bool) done)
        {
            if(atomicLoad(done))
            {
                return;
            }
            if(descendents.length)
            {
                import std.parallelism : parallel;
                foreach(v;parallel(descendents.byValue,1))
                {
                    v.doDescent(done);
                }
            }
            else
            {
                foreach(piece;tetriminosAsList)
                {
                    auto newState = state;
                    newState.piece.pieceType = piece;
                    newState.playOptimally();
                    append(newState,piece);
                }
            }
            depth++;
        }
        Tetrimino get()
        {
            if(dropped != Tetrimino.None)
            {
                return dropped;
            }
            else if(descendents.length)
            {
                foreach(k,v;descendents)
                {
                    if(v.worst >= worst)
                    {
                        return v.get();
                    }
                }
                return Tetrimino.S;
            }
            else
            {
                return Tetrimino.S;
            }
        }
        size_t getDepth()
        {
            return depth;
        }
        bool onlyOneTree()
        {
            return descendents.length <= 1;
        }
        size_t descendentsNum()
        {
            return descendents.length;
        }
    }
	void generateNext()
	{
        StateSeries state = new StateSeries(*baseState,Tetrimino.None);
        import std.datetime.stopwatch;
        StopWatch sw = StopWatch(AutoStart.yes);
        while(true)
        {
            import core.time : msecs;
            sw.reset();
            state.doDescent(done);
            state.prune(sw);
            atomicStore(nextCached, state.get());
            depth = state.getDepth();
            if(done || state.onlyOneTree || sw.peek() > msecs(2000))
            {
                return;
            }
        }
	}
	Tetrimino front()
	{
		return nextCached;
	}
	size_t length()
	{
		return 1;
	}
	void popFront()
	{
        done = true;
        working.workForce();
        done = false;
        working = cast(typeof(working))task(&generateNext);
        taskPool.put(working);
	}
	Tetrimino peek(size_t n)
	{
		return nextCached;
	}
    void draw() {
        import arsd.game : makeCachedPrimitive;
        import app : Hatetris;
        import std.conv : to;
        makeCachedPrimitive!({ 
            Hatetris.font.drawString(70,180,"Moves");
            Hatetris.font.drawString(70,195,"looked ahead:");
             })();
        Hatetris.font.drawString(70,210,depth.to!string);
    }
}

class TGenerator : TetriminoGenerator
{
	Tetrimino front()
	{
		return Tetrimino.T;
	}
	size_t length()
	{
		return 6;
	}
	void popFront()
	{
		return;
	}
	Tetrimino peek(size_t n)
	{
		return front();
	}
    void draw() {}
}