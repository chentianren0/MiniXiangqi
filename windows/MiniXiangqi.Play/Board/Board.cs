// The board's vocabulary: points, pieces, and the position a FEN denotes.
//
// This file reads FEN; it never judges one. Legality, adjudication, and the
// legal-move set all come from the core, and nothing here re-derives them. It
// is the C# counterpart of apple/MiniXiangqi/Board/Board.swift, deliberately
// so: the board, the pieces, and the game-state markers are one shared visual
// identity across platforms, and two frontends that disagree about what a
// square is called would not have one.

namespace MiniXiangqi.Play;

/// <summary>Which side a piece belongs to.</summary>
public enum Side
{
    Red,
    Black,
}

/// <summary>
/// One of the 49 points, named <c>a1</c> through <c>g7</c>: files <c>a</c>–<c>g</c>
/// from Red's left, ranks <c>1</c>–<c>7</c> from Red's back rank.
/// </summary>
public readonly record struct Square(int File, int Rank)
{
    /// <summary>Seven points a side. Not a count of cells: the grid is 6 by 6.</summary>
    public const int Count = 7;

    /// <summary>The canonical name, which is what the core exchanges.</summary>
    public string Name => $"{(char)('a' + File)}{Rank + 1}";

    public bool OnBoard => (uint)File < Count && (uint)Rank < Count;

    public static Square? Parse(ReadOnlySpan<char> name)
    {
        if (name.Length != 2)
        {
            return null;
        }

        Square square = new(name[0] - 'a', name[1] - '1');
        return square.OnBoard ? square : null;
    }
}

/// <summary>The five piece types this variant has. No advisors and no elephants.</summary>
public enum PieceKind
{
    General,
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
        (PieceKind.Chariot, Side.Red) => "俥",
        (PieceKind.Chariot, Side.Black) => "车",
        (PieceKind.Horse, Side.Red) => "傌",
        (PieceKind.Horse, Side.Black) => "马",
        (PieceKind.Cannon, Side.Red) => "炮",
        (PieceKind.Cannon, Side.Black) => "砲",
        (PieceKind.Soldier, Side.Red) => "兵",
        _ => "卒",
    };

    /// <summary>The FEN letter, lowercase, as the placement field spells it.</summary>
    public static PieceKind? FromFen(char letter) => char.ToLowerInvariant(letter) switch
    {
        'k' => PieceKind.General,
        'r' => PieceKind.Chariot,
        'n' => PieceKind.Horse,
        'c' => PieceKind.Cannon,
        'p' => PieceKind.Soldier,
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
    private readonly Piece?[] _pieces = new Piece?[Square.Count * Square.Count];

    public static readonly Placement Empty = new();

    private Placement()
    {
    }

    /// <summary>
    /// Parses the piece-placement field, which lists rank 7 first and rank 1
    /// last. A malformed field yields an empty board rather than a throw: the
    /// FEN came from the core, so a failure here is a bug to see on screen.
    /// </summary>
    public Placement(string fen)
    {
        int space = fen.IndexOf(' ');
        ReadOnlySpan<char> placement = space < 0 ? fen : fen.AsSpan(0, space);

        int row = 0;
        int file = 0;
        foreach (char character in placement)
        {
            if (character == '/')
            {
                row++;
                file = 0;
                continue;
            }

            if (char.IsAsciiDigit(character))
            {
                file += character - '0';
                continue;
            }

            int rank = Square.Count - 1 - row;
            Side side = char.IsAsciiLetterUpper(character) ? Side.Red : Side.Black;
            PieceKind? kind = PieceKinds.FromFen(character);
            Square square = new(file, rank);
            if (kind is { } known && square.OnBoard)
            {
                _pieces[Index(square)] = new Piece(known, side);
            }

            file++;
        }
    }

    public Piece? this[Square square] =>
        square.OnBoard ? _pieces[Index(square)] : null;

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
                return new Square(index % Square.Count, index / Square.Count);
            }
        }

        return null;
    }

    private static int Index(Square square) => (square.Rank * Square.Count) + square.File;
}

/// <summary>
/// A move in the frozen canonical notation, <c>"&lt;from&gt;&lt;to&gt;"</c>. There is no
/// suffix: this ruleset has no promotion, castling, en passant, drop, or gating.
/// </summary>
public readonly record struct Move(Square From, Square To)
{
    public string Text => From.Name + To.Name;

    public static Move? Parse(string? text)
    {
        if (text is not { Length: 4 })
        {
            return null;
        }

        if (Square.Parse(text.AsSpan(0, 2)) is not { } from ||
            Square.Parse(text.AsSpan(2, 2)) is not { } to)
        {
            return null;
        }

        return new Move(from, to);
    }
}
