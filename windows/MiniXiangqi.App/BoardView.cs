// The board, on screen: one Win2D canvas, and forty-nine points over it.
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
using MiniXiangqi.Play;

namespace MiniXiangqi.App;

public sealed partial class BoardView : Grid
{
    private readonly CanvasControl _canvas = new();
    private readonly Canvas _points = new();
    private readonly Dictionary<Square, Button> _buttons = [];

    private BoardScene _scene = BoardScene.Of(Placement.Empty);
    private BoardGeometry _geometry = new(BoardGeometry.MinimumPitch);

    /// <param name="interactive">
    /// Whether the board has points at all. The pre-start preview does not: it
    /// "shows the initial board as a noninteractive preview", and a preview has
    /// nothing to interact with — saying so is what keeps a screen reader from
    /// offering forty-nine points that answer to nothing, and what keeps a click
    /// on it from meaning anything.
    /// </param>
    public BoardView(bool interactive = true)
    {
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

        for (int rank = 0; rank < Square.Count; rank++)
        {
            for (int file = 0; file < Square.Count; file++)
            {
                Square square = new(file, rank);
                Button button = new()
                {
                    Tag = square,
                    Style = (Style)Application.Current.Resources["BoardPointStyle"],
                };
                button.Click += (_, _) => PointTapped?.Invoke(square);

                // A point's tap is answered by its own Click and stops here.
                //
                // This is the fix for a reported defect: selecting a piece
                // appeared to need a *double* click. What was wrong is below, in
                // OnTapped — the filter that was supposed to let a point's tap
                // pass unanswered could not match — and the effect of the tap
                // reaching the board's own handler is a background cancel
                // arriving immediately behind the selection the same click had
                // just made. The double click worked because the second tap of a
                // double tap raises DoubleTapped rather than Tapped, so no
                // cancel followed it and the selection stood.
                button.Tapped += (_, tapped) => tapped.Handled = true;

                button.PointerEntered += (_, _) => PointerOverChanged?.Invoke(square);
                button.PointerExited += (_, _) => PointerOverChanged?.Invoke(null);
                AutomationProperties.SetAutomationId(button, $"point-{square.Name}");
                _buttons[square] = button;
                _points.Children.Add(button);
            }
        }

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
            Width = value.BlockSide;
            Height = value.BlockSide;
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
            _scene = value;
            if (reorient)
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

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args) =>
        BoardPainter.Draw(args.DrawingSession, _scene, _geometry, PieceStyle);

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

    private void Place()
    {
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
