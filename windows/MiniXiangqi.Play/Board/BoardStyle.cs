// A piece style: the disc, its resting shadow, and the board surface beneath
// it, as one coherent look.
//
// The values are apple/MiniXiangqi/Board/BoardStyle.swift's, to the digit, for
// the reason BoardGeometry gives: docs/interaction-design.md fixes the contrast
// gates each colour must reach and leaves the values to the style's colour
// work, that work was done once against a rendered board, and the board is one
// shared visual identity across platforms.
//
// Only 传统 is implemented, exactly as on the Mac: 现代 and 高对比度 are accepted
// and still to come, which is why every value a painter reads goes through this
// type rather than being written into it.

namespace MiniXiangqi.Play;

/// <summary>
/// A colour, as the three sRGB bytes a Windows colour is built from. The
/// painter converts; nothing below it needs a platform type to hold a value the
/// contract states.
/// </summary>
public readonly record struct Rgb(byte R, byte G, byte B)
{
    /// <summary>From the 0–1 components the accepted values are written in.</summary>
    public static Rgb Of(double red, double green, double blue) => new(
        (byte)Math.Round(red * 255),
        (byte)Math.Round(green * 255),
        (byte)Math.Round(blue * 255));
}

/// <summary>
/// A disc shadow, held as components. Presentation only: no style may rely on
/// one to satisfy a contrast requirement.
/// </summary>
public readonly record struct BoardShadow(double Opacity, double Radius, double Y);

public sealed record BoardStyle(
    Rgb BoardSurface,
    Rgb Grid,
    Rgb DiscFace,
    Rgb RedDiscEdge,
    Rgb BlackDiscEdge,
    double RedDiscEdgeStroke,
    double BlackDiscEdgeStroke,
    Rgb RedSymbol,
    Rgb BlackSymbol,
    Rgb ActiveInk,
    Rgb RecordInk,
    BoardShadow RestingShadow,
    BoardShadow LiftShadow)
{
    public Rgb DiscEdge(Side side) => side == Side.Red ? RedDiscEdge : BlackDiscEdge;

    /// <summary>As a multiple of the pitch.</summary>
    public double DiscEdgeStroke(Side side) => side == Side.Red ? RedDiscEdgeStroke : BlackDiscEdgeStroke;

    public Rgb Symbol(Side side) => side == Side.Red ? RedSymbol : BlackSymbol;

    /// <summary>
    /// 传统 — the default. Both sides use the same warm light disc face, as a
    /// physical set does, with the symbols themselves in the Red and Black role
    /// colours. The Black disc carries a heavier ring, so a second non-colour
    /// channel is always present.
    /// </summary>
    public static readonly BoardStyle Traditional = new(
        BoardSurface: Rgb.Of(0.910, 0.847, 0.741),
        Grid: Rgb.Of(0.361, 0.286, 0.192),
        DiscFace: Rgb.Of(0.973, 0.937, 0.851),
        RedDiscEdge: Rgb.Of(0.478, 0.384, 0.259),
        BlackDiscEdge: Rgb.Of(0.114, 0.102, 0.086),
        RedDiscEdgeStroke: 0.014,
        BlackDiscEdgeStroke: 0.028,
        RedSymbol: Rgb.Of(0.616, 0.129, 0.098),
        BlackSymbol: Rgb.Of(0.086, 0.078, 0.067),
        ActiveInk: Rgb.Of(0.075, 0.294, 0.278),
        RecordInk: Rgb.Of(0.302, 0.451, 0.435),
        RestingShadow: new BoardShadow(0.22, 0.030, 0.018),
        LiftShadow: new BoardShadow(0.30, 0.075, 0.045));
}
