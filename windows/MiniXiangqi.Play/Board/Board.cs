// The board's vocabulary: games, points, pieces, and the position a FEN denotes.
//
// This file reads FEN; it never judges one. Legality, adjudication, and the
// legal-move set all come from the core, and nothing here re-derives them. It
// is the C# counterpart of apple/MiniXiangqi/Board/Board.swift, deliberately
// so: the board, the pieces, and the game-state markers are one shared visual
// identity across platforms, and two frontends that disagree about what a
// square is called would not have one.

using System.Collections.Immutable;
using MiniXiangqi.Core;

namespace MiniXiangqi.Play;

/// <summary>
/// The dimensions and fixed markings of one game's board. Rules and legality
/// still belong to the core; this is only the topology the Windows UI presents.
/// </summary>
public readonly record struct BoardDefinition(
    int FileCount,
    int RankCount,
    ImmutableArray<BoardDefinition.Palace> Palaces,
    int? RiverAfterRank)
{
    /// <summary>A three-by-three palace, expressed as inclusive point indices.</summary>
    public readonly record struct Palace(
        int FirstFile,
        int LastFile,
        int FirstRank,
        int LastRank);

    public static BoardDefinition MiniXiangqi { get; } = new(
        7,
        7,
        [new Palace(2, 4, 0, 2), new Palace(2, 4, 4, 6)],
        RiverAfterRank: null);

    public static BoardDefinition Xiangqi { get; } = new(
        9,
        10,
        [new Palace(3, 5, 0, 2), new Palace(3, 5, 7, 9)],
        RiverAfterRank: 4);

    /// <summary>The two profiles, for dimensions that must survive a game switch.</summary>
    public static ImmutableArray<BoardDefinition> All { get; } = [MiniXiangqi, Xiangqi];

    public int SquareCount => FileCount * RankCount;

    public bool Contains(Square square) =>
        (uint)square.File < (uint)FileCount && (uint)square.Rank < (uint)RankCount;

    public static BoardDefinition For(GameKind game) => game switch
    {
        GameKind.MiniXiangqi => MiniXiangqi,
        GameKind.Xiangqi => Xiangqi,
        _ => throw new ArgumentOutOfRangeException(nameof(game), game, "Unknown game kind."),
    };
}

/// <summary>Which side a piece belongs to.</summary>
public enum Side
{
    Red,
    Black,
}

/// <summary>
/// One point, named by a file from Red's left and a rank from Red's back rank.
/// The board definition, not the value itself, decides whether it is in bounds.
/// </summary>
public readonly record struct Square(int File, int Rank)
{
    /// <summary>The canonical name, which is what the core exchanges.</summary>
    public string Name => $"{(char)('a' + File)}{Rank + 1}";

    public bool On(BoardDefinition board) => board.Contains(this);

    /// <summary>Parse one canonical coordinate against an explicit board.</summary>
    public static Square? Parse(ReadOnlySpan<char> name, BoardDefinition board)
    {
        if (name.Length < 2 || name[0] is < 'a' or > 'z' || name[1] == '0')
        {
            return null;
        }

        int displayedRank = 0;
        foreach (char digit in name[1..])
        {
            if (digit is < '0' or > '9')
            {
                return null;
            }

            displayedRank = (displayedRank * 10) + (digit - '0');
            if (displayedRank > board.RankCount)
            {
                return null;
            }
        }

        Square square = new(name[0] - 'a', displayedRank - 1);
        return square.On(board) ? square : null;
    }
}

/// <summary>The seven Xiangqi piece types; Mini Xiangqi uses five of them.</summary>
public enum PieceKind
{
    General,
    Advisor,
    Elephant,
    Chariot,
    Horse,
    Cannon,
    Soldier,
}

public static class PieceKinds
{
    /// <summary>
    /// The accepted piece characters. Every type has a distinct Red and Black
    /// form, so the sides are told apart by glyph and never by colour alone.
    /// They are game content: identical in every supported language, never
    /// translated, and never in the string table.
    /// </summary>
    public static string Character(this PieceKind kind, Side side) => (kind, side) switch
    {
        (PieceKind.General, Side.Red) => "帅",
        (PieceKind.General, Side.Black) => "将",
        (PieceKind.Advisor, Side.Red) => "仕",
        (PieceKind.Advisor, Side.Black) => "士",
        (PieceKind.Elephant, Side.Red) => "相",
        (PieceKind.Elephant, Side.Black) => "象",
        (PieceKind.Chariot, Side.Red) => "俥",
        (PieceKind.Chariot, Side.Black) => "车",
        (PieceKind.Horse, Side.Red) => "傌",
        (PieceKind.Horse, Side.Black) => "马",
        (PieceKind.Cannon, Side.Red) => "炮",
        (PieceKind.Cannon, Side.Black) => "砲",
        (PieceKind.Soldier, Side.Red) => "兵",
        (PieceKind.Soldier, Side.Black) => "卒",
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown piece kind."),
    };

    /// <summary>The FEN letter, lowercase, as the placement field spells it.</summary>
    public static PieceKind? FromFen(char letter) => letter switch
    {
        'k' or 'K' => PieceKind.General,
        'a' or 'A' => PieceKind.Advisor,
        'b' or 'B' => PieceKind.Elephant,
        'r' or 'R' => PieceKind.Chariot,
        'n' or 'N' => PieceKind.Horse,
        'c' or 'C' => PieceKind.Cannon,
        'p' or 'P' => PieceKind.Soldier,
        _ => null,
    };
}

public readonly record struct Piece(PieceKind Kind, Side Side);

/// <summary>
/// The placement a FEN denotes. Only the placement: the side to move, the
/// counters, and every rule question belong to the core's evaluation.
/// </summary>
public sealed class Placement
{
    private readonly Piece?[] _pieces;

    private Placement(GameKind game)
    {
        Game = game;
        Board = BoardDefinition.For(game);
        _pieces = new Piece?[Board.SquareCount];
    }

    public GameKind Game { get; }

    public BoardDefinition Board { get; }

    public static Placement EmptyFor(GameKind game) => new(game);

    /// <summary>
    /// Parses the piece-placement field, which lists the highest rank first and
    /// rank 1 last. A malformed field yields an empty board rather than a throw:
    /// the FEN came from the core, so a failure here is a bug to see on screen.
    /// </summary>
    public Placement(string fen, GameKind game)
    {
        Game = game;
        Board = BoardDefinition.For(game);
        _pieces = Parse(fen, Board);
    }

    public Piece? this[Square square] =>
        square.On(Board) ? _pieces[Index(square)] : null;

    /// <summary>
    /// Where a side's general stands. Not a rule and not an adjudication — the
    /// core says whether a side is in check, and this only says which disc to
    /// draw the rings around.
    /// </summary>
    public Square? General(Side side)
    {
        for (int index = 0; index < _pieces.Length; index++)
        {
            if (_pieces[index] is { Kind: PieceKind.General } piece && piece.Side == side)
            {
                return new Square(index % Board.FileCount, index / Board.FileCount);
            }
        }

        return null;
    }

    private int Index(Square square) => (square.Rank * Board.FileCount) + square.File;

    private static Piece?[] Parse(string fen, BoardDefinition board)
    {
        Piece?[] empty = new Piece?[board.SquareCount];
        int space = fen.IndexOf(' ');
        string placement = space < 0 ? fen : fen[..space];
        string[] lines = placement.Split('/', StringSplitOptions.None);
        if (lines.Length != board.RankCount)
        {
            return empty;
        }

        Piece?[] parsed = new Piece?[board.SquareCount];
        for (int row = 0; row < lines.Length; row++)
        {
            int rank = board.RankCount - 1 - row;
            int file = 0;
            foreach (char character in lines[row])
            {
                if (character is >= '1' and <= '9')
                {
                    int skip = character - '0';
                    if (file + skip > board.FileCount)
                    {
                        return empty;
                    }

                    file += skip;
                    continue;
                }

                PieceKind? kind = PieceKinds.FromFen(character);
                if (kind is not { } known || file >= board.FileCount)
                {
                    return empty;
                }

                Side side = character is >= 'A' and <= 'Z' ? Side.Red : Side.Black;
                parsed[(rank * board.FileCount) + file] = new Piece(known, side);
                file++;
            }

            if (file != board.FileCount)
            {
                return empty;
            }
        }

        return parsed;
    }
}

/// <summary>
/// A move in the frozen canonical notation, <c>"&lt;from&gt;&lt;to&gt;"</c>. There is no
/// suffix: this ruleset has no promotion, castling, en passant, drop, or gating.
/// </summary>
public readonly record struct Move(Square From, Square To)
{
    public string Text => From.Name + To.Name;

    public static Move? Parse(string? text, BoardDefinition board)
    {
        if (text is null || text.Length is < 4 or > 6)
        {
            return null;
        }

        ReadOnlySpan<char> characters = text.AsSpan();
        Move? parsed = null;
        int matches = 0;
        foreach (int split in (int[])[2, 3])
        {
            if (split >= characters.Length ||
                Square.Parse(characters[..split], board) is not { } from ||
                Square.Parse(characters[split..], board) is not { } to)
            {
                continue;
            }

            parsed = new Move(from, to);
            matches++;
        }

        return matches == 1 ? parsed : null;
    }
}
