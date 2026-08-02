// The board, on screen: one Win2D canvas, and forty-nine or ninety points over it.
//
// The picture is BoardPainter's, which is the same code the offscreen renders
// use. What this adds is what a picture cannot have: points a pointer can hit
// and a screen reader can name. Each one is placed at the same centre the
// painter draws that point at, from the same geometry, rather than laid out by
// a panel that happens to divide the board evenly — the Apple frontend had a
// stray inset there once, and it shifted every point by a fraction of a cell
// while remaining perfectly self-consistent, so clicking by name still worked
// and no test could see it. Sharing the geometry is what makes the two agree.

using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using MiniXiangqi.Board;
using MiniXiangqi.Core;
using MiniXiangqi.Play;

namespace MiniXiangqi.App;

public sealed partial class BoardView : Grid
{
    private readonly CanvasControl _canvas = new();
    private readonly Canvas _points = new();
    private readonly Dictionary<Square, Button> _buttons = [];
    private readonly bool _interactive;

    private BoardScene _scene;
    private BoardGeometry _geometry;

    /// <param name="initialGame">
    /// The explicit topology this otherwise-empty view has before its first
    /// scene is assigned. It is initial layout state, never a fallback for a
    /// scene whose game is unknown.
    /// </param>
    /// <param name="interactive">
    /// Whether the board has points at all. The pre-start preview does not: it
    /// "shows the initial board as a noninteractive preview", and a preview has
    /// nothing to interact with — saying so is what keeps a screen reader from
    /// offering forty-nine or ninety points that answer to nothing, and keeps a click
    /// on it from meaning anything.
    /// </param>
    public BoardView(GameKind initialGame, bool interactive = true)
    {
        _interactive = interactive;
        BoardDefinition initialBoard = BoardDefinition.For(initialGame);
        _scene = BoardScene.Of(Placement.EmptyFor(initialGame));
        _geometry = new BoardGeometry(initialBoard, BoardGeometry.MinimumPitch(initialBoard));

        // **A board view is born at the size its geometry says.**
        //
        // This is the hole the owner's tour actually fell into, and it is worth
        // stating exactly, because the two-line fix looks like housekeeping. The
        // Geometry setter below assigns Width and Height *past* its own equality
        // guard, so a set whose value equals the one this field was initialized
        // with returns early and leaves the view unsized. The window's minimum
        // parks the board host at exactly the pitch floor, so the very first fit
        // in the smallest window is a set of the 44-point geometry — the same
        // value — and the view kept Auto width and height. Unsized inside a Grid
        // and centred, it measures nothing and paints nothing: a board page with
        // no board on it and nothing said.
        //
        // Saying the size here rather than moving the assignments above the guard
        // keeps the invariant this class's own rather than the caller's: it holds
        // from construction, and every set that changes anything re-establishes
        // it. The guard below stays what it was for — the work, not the size.
        Width = _geometry.BlockWidth;
        Height = _geometry.BlockHeight;

        _canvas.Draw += OnDraw;
        _canvas.ClearColor = Microsoft.UI.Colors.Transparent;
        Children.Add(_canvas);
        Children.Add(_points);

        if (!interactive)
        {
            IsHitTestVisible = false;
            AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
            Loaded += (_, _) => Place();
            return;
        }

        RebuildButtons();

        Tapped += OnTapped;
        PointerExited += (_, _) => PointerOverChanged?.Invoke(null);
        Loaded += (_, _) => Place();
    }

    /// <summary>A click on a point.</summary>
    public event Action<Square>? PointTapped;

    /// <summary>A click anywhere on the board that is not a point.</summary>
    public event Action? BackgroundTapped;

    /// <summary>Where the pointer is, or null when it has left the board.</summary>
    public event Action<Square?>? PointerOverChanged;

    /// <summary>The piece style the board is drawn in. Only 传统 exists so far.</summary>
    public BoardStyle PieceStyle { get; set; } = BoardStyle.Traditional;

    /// <summary>
    /// The geometry this view draws at, and the size it takes.
    ///
    /// The guard is about the work — replacing every button's position and
    /// invalidating the canvas — and never about the size, which the constructor
    /// has already stated and which only a *changed* geometry can move. Setting
    /// the same geometry twice is a no-op that leaves a correctly sized view;
    /// it did not use to, and that is the comment in the constructor.
    /// </summary>
    public BoardGeometry Geometry
    {
        get => _geometry;
        set
        {
            if (_geometry == value)
            {
                return;
            }

            _geometry = value;
            Width = value.BlockWidth;
            Height = value.BlockHeight;
            Place();
            _canvas.Invalidate();
        }
    }

    public BoardScene Scene
    {
        get => _scene;
        set
        {
            bool reorient = _scene.Flipped != value.Flipped;
            bool rebuild = _scene.Game != value.Game;
            _scene = value;
            if (rebuild)
            {
                RebuildButtons();
            }
            else if (reorient)
            {
                Place();
            }

            Describe();
            _canvas.Invalidate();
        }
    }

    /// <summary>
    /// Release the canvas's device resources. A Win2D canvas holds them until
    /// it is told to let go, and a window that is closing is exactly that
    /// moment.
    /// </summary>
    public void Release() => _canvas.RemoveFromVisualTree();

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        if (_geometry.Board == _scene.Board)
        {
            BoardPainter.Draw(args.DrawingSession, _scene, _geometry, PieceStyle);
        }
    }

    /// <summary>
    /// A tap on the board that was not a point's. Anything else on the board —
    /// the coordinate strips, the margin, the space between points — is outside
    /// the points, and tapping outside the board cancels the selection.
    ///
    /// **The test below used to ask the wrong element.** A point's Button is
    /// templated down to a bare <c>Border</c> with no <c>Tag</c>, so the element
    /// a tap originates on is that Border and never the Button:
    /// <c>OriginalSource is FrameworkElement { Tag: Square }</c> could not match
    /// for any tap on any point, and every one of them fell through to the
    /// cancel below. Walking to the Button is what the test meant, and the
    /// handler above is what stops the tap before it ever reaches here.
    ///
    /// Both are kept. Which of the two is load-bearing depends on whether this
    /// platform routes a tap past a Button that has already handled the pointer
    /// press, and that is a question no headless process can answer — a WinUI 3
    /// window cannot be launched over SSH. Each is a correct statement about the
    /// interaction on its own, so the interaction does not depend on the answer.
    /// </summary>
    private void OnTapped(object sender, TappedRoutedEventArgs args)
    {
        if (IsPointTap(args.OriginalSource as DependencyObject))
        {
            return;
        }

        BackgroundTapped?.Invoke();
    }

    /// <summary>
    /// Whether an element is a point, or is inside one. It walks the visual tree
    /// rather than testing the element itself, because a control's own template
    /// stands between a tap and the control it belongs to.
    /// </summary>
    private static bool IsPointTap(DependencyObject? source)
    {
        for (DependencyObject? node = source; node is not null;
             node = VisualTreeHelper.GetParent(node))
        {
            if (node is FrameworkElement { Tag: Square })
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Build exactly one disjoint pitch-sized hit element for every point in
    /// the scene's selected game. A single view can survive a game switch, so
    /// these are topology rather than constructor state.
    /// </summary>
    private void RebuildButtons()
    {
        _points.Children.Clear();
        _buttons.Clear();
        if (!_interactive)
        {
            return;
        }

        for (int rank = 0; rank < _scene.Board.RankCount; rank++)
        {
            for (int file = 0; file < _scene.Board.FileCount; file++)
            {
                Square square = new(file, rank);
                Button button = new()
                {
                    Tag = square,
                    Style = (Style)Application.Current.Resources["BoardPointStyle"],
                };
                button.Click += (_, _) => PointTapped?.Invoke(square);

                // A point's tap is answered by its own Click and stops here.
                // Otherwise the board's background handler would cancel the
                // selection immediately behind the click that made it.
                button.Tapped += (_, tapped) => tapped.Handled = true;

                button.PointerEntered += (_, _) => PointerOverChanged?.Invoke(square);
                button.PointerExited += (_, _) => PointerOverChanged?.Invoke(null);
                AutomationProperties.SetAutomationId(button, $"point-{square.Name}");
                _buttons[square] = button;
                _points.Children.Add(button);
            }
        }

        Place();
    }

    private void Place()
    {
        // Scene and geometry are assigned separately by the host. A game switch
        // sets the scene first and immediately refits it; do not briefly place a
        // 9-by-10 hit topology through the previous game's geometry in between.
        if (_geometry.Board != _scene.Board)
        {
            return;
        }

        double strip = _geometry.StripExtent;
        double pitch = _geometry.Pitch;
        foreach ((Square square, Button button) in _buttons)
        {
            (double x, double y) = _geometry.Center(square, _scene.Flipped);
            button.Width = pitch;
            button.Height = pitch;
            Canvas.SetLeft(button, strip + x - (pitch / 2));
            Canvas.SetTop(button, strip + y - (pitch / 2));
        }
    }

    private void Describe()
    {
        foreach ((Square square, Button button) in _buttons)
        {
            AutomationProperties.SetName(button, _scene.Describe(square));
        }
    }
}
