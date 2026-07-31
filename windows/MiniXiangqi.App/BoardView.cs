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
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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

    public BoardView()
    {
        _canvas.Draw += OnDraw;
        _canvas.ClearColor = Microsoft.UI.Colors.Transparent;
        Children.Add(_canvas);
        Children.Add(_points);

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

    private void OnTapped(object sender, TappedRoutedEventArgs args)
    {
        // A point's own button has already answered for itself; anything else
        // on the board — the coordinate strips, the margin — is outside, and
        // tapping outside the board cancels the selection.
        if (args.OriginalSource is FrameworkElement { Tag: Square })
        {
            return;
        }

        BackgroundTapped?.Invoke();
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
