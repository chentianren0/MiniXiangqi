// The play screen: the board, the pieces, and a live game against the AI.
//
// Everything below is presentation and wiring. What a click means, which
// controls the mode offers, when the machine thinks, and what happens when it
// answers all live in MiniXiangqi.Play's PlaySession, which has no window and
// can therefore be run on a machine nobody is logged into. This file turns that
// state into XAML and turns XAML's events back into calls on it.
//
// **The temporary seam.** The setup screen and the Play home arrive in the next
// pull request. Until they do, this window resumes the single active game or
// creates one exactly as the walking skeleton did — human versus AI, the human
// Red and moving first, at 快速 — with no way to choose. That is the whole of
// what the flows pull request replaces here: it owns the Play home, the two
// pre-start states, 开始对局, the save-and-continue confirmation, and the
// navigation container around all of them. Free Play needs none of this file's
// help: PlaySession already plays it, the play-control cluster already composes
// for it, and MiniXiangqi.Smoke already drives a game of it — it has no entry
// point, and that entry point is the flows pull request's.

using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;
using MiniXiangqi.Play;

namespace MiniXiangqi.App;

public sealed partial class MainWindow : Window
{
    private readonly BoardView _board = new();
    private readonly MiniXiangqiCore? _core;
    private readonly PlaySession? _play;
    private PlayAlert _showing = PlayAlert.None;
    private ResultNotice _announced = ResultNotice.None;
    private int _recordLength = -1;

    public MainWindow()
    {
        InitializeComponent();
        Title = Strings.Get("app.displayName");
        Root.Loaded += (_, _) => WatchTheScale();

        BoardHost.Children.Add(_board);
        _board.HorizontalAlignment = HorizontalAlignment.Center;
        _board.VerticalAlignment = VerticalAlignment.Center;
        _board.PointTapped += OnPointTapped;
        _board.BackgroundTapped += OnBackgroundTapped;
        _board.PointerOverChanged += OnPointerOver;
        Root.KeyDown += OnKeyDown;

        string assets = Path.Combine(AppContext.BaseDirectory, "assets");
        string store = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MiniXiangqi",
            "store");

        try
        {
            _core = MiniXiangqiCore.Start(store, assets);
        }
        catch (MxqException failure)
        {
            ShowFailure("failure.coreDidNotStart", failure);
            return;
        }

        try
        {
            // The seam. One game, the skeleton's configuration, no choice.
            GameSession game = _core.ResumeOrCreate(
                humanSide: Mxq.MXQ_COLOR_RED,
                aiLevel: Mxq.MXQ_AI_LEVEL_FAST,
                firstMoverChoice: Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
                movetimeMs: Mxq.MXQ_MOVETIME_FAST_MS);
            _play = new PlaySession(_core, game, new WindowScheduler(DispatcherQueue));
        }
        catch (MxqException failure)
        {
            ShowFailure("failure.gameDidNotStart", failure);
            return;
        }

        _play.Changed += Refresh;
        Refresh();
        _play.Begin();

        Closed += (_, _) =>
        {
            _board.Release();
            _play?.Dispose();
            _core?.Dispose();
        };
    }

    // Layout.

    /// <summary>
    /// The window's minimum follows the display scale, because the two sides of
    /// the sum are measured in different units.
    ///
    /// Everything XAML lays out — the board block, the panel, the air around
    /// them — is in device-independent pixels. <c>OverlappedPresenter</c> is not
    /// a XAML object: it is the <c>AppWindow</c>'s presenter, and the whole
    /// <c>AppWindow</c> surface is documented in physical pixels — <c>Size</c>,
    /// <c>ClientSize</c>, <c>Resize</c>, <c>Move</c> — with the XAML island's
    /// own scale exposed separately as <c>XamlRoot.RasterizationScale</c>
    /// precisely because the two do not agree. These properties are also what
    /// the presenter answers <c>WM_GETMINMAXINFO</c> with, and that message is
    /// physical pixels by definition. Setting a DIP figure there would give a
    /// 150 % display a floor two thirds of the intended one, which is exactly
    /// the size at which the board stops fitting.
    ///
    /// The scale can change while the window is open — a drag to another
    /// display, a settings change — so the floor is recomputed when it does.
    /// </summary>
    private void WatchTheScale()
    {
        if (Root.XamlRoot is not { } root)
        {
            return;
        }

        StopShrinkingAtTheFloors(root.RasterizationScale);
        root.Changed += (sender, _) => StopShrinkingAtTheFloors(sender.RasterizationScale);
    }

    /// <summary>
    /// Both the board and the chrome have floors, so the window has one too,
    /// and it stops resizing there rather than either becoming unusable. The
    /// board block at the accepted 44-point pitch is 340 square, the air around
    /// it is 24 a side, and the panel beside it is 260.
    /// </summary>
    private void StopShrinkingAtTheFloors(double scale)
    {
        if (AppWindow.Presenter is not Microsoft.UI.Windowing.OverlappedPresenter presenter)
        {
            return;
        }

        BoardGeometry floor = new(BoardGeometry.MinimumPitch);
        presenter.PreferredMinimumWidth = (int)Math.Ceiling((floor.BlockSide + 48 + 260) * scale);
        presenter.PreferredMinimumHeight = (int)Math.Ceiling((floor.BlockSide + 48) * scale);
    }

    private void OnBoardHostSizeChanged(object sender, SizeChangedEventArgs args)
    {
        // The board is square and is sized to the largest square fitting both
        // the available width and the height left after the surrounding chrome,
        // so it never overflows a short window.
        double side = Math.Min(
            args.NewSize.Width - BoardHost.Padding.Left - BoardHost.Padding.Right,
            args.NewSize.Height - BoardHost.Padding.Top - BoardHost.Padding.Bottom);
        if (side <= 0)
        {
            return;
        }

        // Fitting refuses rather than clamps when even the floor does not fit,
        // which is the shape the Apple frontend's geometry has and for the same
        // reason: a board below the floor is a decision, and a decision belongs
        // where somebody can see it. Here the decision is the floor anyway —
        // the window's own minimum should have made this unreachable, and if a
        // scale change beats it there, an oversized board that can still be
        // played beats a board that is not drawn.
        _board.Geometry = BoardGeometry.Fitting(side)
            ?? new BoardGeometry(BoardGeometry.MinimumPitch);
    }

    // Board input.

    private void OnPointTapped(Square square)
    {
        if (Dismissed())
        {
            return;
        }

        _play?.Tap(square);
    }

    private void OnBackgroundTapped()
    {
        if (Dismissed())
        {
            return;
        }

        _play?.CancelSelection();
    }

    private void OnPointerOver(Square? square) => _play?.Hover(square);

    private void OnKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == Windows.System.VirtualKey.Escape && Dismissed())
        {
            args.Handled = true;
        }
    }

    /// <summary>
    /// The notice is dismissible by its own close control, by the platform's
    /// cancel key, or by a click on the board. Answers whether this interaction
    /// was spent putting it away.
    /// </summary>
    private bool Dismissed()
    {
        if (_play is null || _play.Notice == ResultNotice.None)
        {
            return false;
        }

        _play.DismissNotice();
        return true;
    }

    // Play controls. What the cluster carries is the mode's, and while a game is
    // finished there is no draw left to judge, so that slot carries the
    // concluding action instead.

    private void OnUndo(object sender, RoutedEventArgs args) => _play?.Undo();

    private void OnMiddle(object sender, RoutedEventArgs args)
    {
        if (_play is null)
        {
            return;
        }

        if (_play.IsOver)
        {
            _play.NewGame();
        }
        else
        {
            _play.RequestClaimDraw();
        }
    }

    private void OnTrailing(object sender, RoutedEventArgs args)
    {
        if (_play is null)
        {
            return;
        }

        if (_play.CanFlip)
        {
            _play.FlipBoard();
        }
        else
        {
            _play.RequestResign();
        }
    }

    private void OnRetryEngine(object sender, RoutedEventArgs args) => _play?.RetryEngine();

    private void OnDismissNotice(object sender, RoutedEventArgs args) => _play?.DismissNotice();

    private void OnNoticePrimary(object sender, RoutedEventArgs args)
    {
        if (_play is null)
        {
            return;
        }

        if (_play.Notice == ResultNotice.Recorded)
        {
            _play.DismissNotice();
        }
        else
        {
            _play.SaveResult();
        }
    }

    private void OnNoticeSecondary(object sender, RoutedEventArgs args) => _play?.NewGame();

    // Presentation.

    private void Refresh()
    {
        if (_play is not { } play)
        {
            return;
        }

        _board.Scene = play.Scene;

        StatusPrimary.Text = play.PrimaryStatus();
        StatusSecondary.Text = play.SecondaryStatus() ?? string.Empty;
        StatusSecondary.Visibility = StatusSecondary.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;

        bool thinking = play.Activity == AiActivity.Thinking;
        Thinking.IsActive = thinking;
        Thinking.Visibility = thinking ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(Thinking, Strings.Get("status.aiThinking"));

        bool stalled = play.Activity == AiActivity.Stalled;
        Stalled.Visibility = stalled ? Visibility.Visible : Visibility.Collapsed;
        StalledText.Text = Strings.Get("status.aiUnavailable");
        StalledRetry.Content = Strings.Get("control.tryAgain");

        SaveFailure.Visibility = play.MoveNotSaved ? Visibility.Visible : Visibility.Collapsed;
        SaveFailureText.Text = Strings.Get("status.saveFailed");

        ShowControls(play);
        ShowRecord(play);
        ShowNotice(play);
        ShowAlert();
    }

    private void ShowControls(PlaySession play)
    {
        Undo.Content = Strings.Get("control.undo");
        Undo.IsEnabled = play.CanUndo;

        if (play.IsOver)
        {
            Middle.Content = Strings.Get("control.newGame");
            Middle.IsEnabled = true;
        }
        else
        {
            Middle.Content = Strings.Get("control.claimDraw");
            Middle.IsEnabled = play.CanClaimDraw;
        }

        if (play.CanFlip)
        {
            // Free Play cannot resign, having no opponent to resign to, and it
            // is the mode the accepted orientation behaviour gives a flip
            // control.
            Trailing.Content = Strings.Get("control.flipBoard");
            Trailing.IsEnabled = true;
            Trailing.Visibility = Visibility.Visible;
        }
        else
        {
            // Human versus AI carries no board-flip control: the human's own
            // side is already at the bottom, and moving it to the top is
            // disorienting rather than useful.
            Trailing.Content = Strings.Get("control.resign");
            Trailing.IsEnabled = play.CanResign;
            Trailing.Visibility = play.IsOver ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    private void ShowRecord(PlaySession play)
    {
        // The move record, live during play: the core's own canonical
        // coordinate text, paired by full move. It is not a notation rendering
        // and does not pretend to be one.
        //
        // Rebuilt only when the record's length changed, and scrolled to the
        // end only when it grew. Everything on this screen publishes through
        // one event, including the pointer moving from one point to the next,
        // and a reader who has scrolled back through the game must not be
        // yanked to the bottom by moving the mouse.
        IReadOnlyList<string> moves = play.MoveRecord;
        if (moves.Count == _recordLength)
        {
            return;
        }

        bool grew = moves.Count > _recordLength;
        _recordLength = moves.Count;
        RecordRows.Children.Clear();
        for (int index = 0; index < moves.Count; index += 2)
        {
            Grid row = new()
            {
                ColumnDefinitions =
                {
                    new ColumnDefinition { Width = new GridLength(28) },
                    new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) },
                    new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) },
                },
            };

            TextBlock number = new()
            {
                Text = Strings.Format("moveList.rowNumber", (index / 2) + 1),
                TextAlignment = TextAlignment.Right,
                Opacity = 0.6,
                Margin = new Thickness(0, 0, 8, 0),
            };
            Grid.SetColumn(number, 0);
            row.Children.Add(number);

            row.Children.Add(MoveCell(moves[index], 1));
            if (index + 1 < moves.Count)
            {
                row.Children.Add(MoveCell(moves[index + 1], 2));
            }

            RecordRows.Children.Add(row);
        }

        if (grew)
        {
            DispatcherQueue.TryEnqueue(() =>
                RecordScroller.ChangeView(null, RecordScroller.ScrollableHeight, null, disableAnimation: true));
        }
    }

    private static TextBlock MoveCell(string text, int column)
    {
        TextBlock cell = new()
        {
            Text = text,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
        };
        Grid.SetColumn(cell, column);
        return cell;
    }

    private void ShowNotice(PlaySession play)
    {
        if (play.Notice == ResultNotice.None)
        {
            Notice.Visibility = Visibility.Collapsed;
            _announced = ResultNotice.None;
            return;
        }

        Notice.Visibility = Visibility.Visible;
        NoticeTitle.Text = play.NoticeTitle() ?? string.Empty;
        AutomationProperties.SetName(NoticeClose, Strings.Get("control.close"));

        bool recorded = play.Notice == ResultNotice.Recorded;
        NoticeReason.Text = recorded ? string.Empty : play.Reason() ?? string.Empty;
        NoticeReason.Visibility = NoticeReason.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;

        // Before confirmation both actions save, and the default one only
        // saves: when a game ends, keeping the game that was just played is
        // wanted far more often than being dealt the next one. Once recorded,
        // 完成 stands alone — 回放 opens a History record, and History arrives
        // with the pull request that builds it.
        NoticePrimary.Content = Strings.Get(recorded ? "control.done" : "control.save");
        NoticeSecondary.Content = Strings.Get("control.saveAndNewGame");
        NoticeSecondary.Visibility = recorded ? Visibility.Collapsed : Visibility.Visible;

        Announce(play);
    }

    /// <summary>
    /// The result, said out loud once.
    ///
    /// The notice arrives without being asked for and a screen-reader user has
    /// no reason to be looking at it, so it is announced — which is what the
    /// Apple frontend does, through this same `result.announcement` row, and
    /// that is the level this platform owes. A UIA notification is the Windows
    /// equivalent: it is spoken where it happens and moves nothing, so focus
    /// stays where the player put it.
    /// </summary>
    private void Announce(PlaySession play)
    {
        if (_announced == play.Notice)
        {
            return;
        }

        _announced = play.Notice;
        string title = play.NoticeTitle() ?? string.Empty;
        string? reason = play.Notice == ResultNotice.Recorded ? null : play.Reason();
        string spoken = reason is { Length: > 0 }
            ? Strings.Format("result.announcement", title, reason)
            : title;

        AutomationPeer peer = FrameworkElementAutomationPeer.FromElement(NoticeTitle)
            ?? FrameworkElementAutomationPeer.CreatePeerForElement(NoticeTitle);
        peer.RaiseNotificationEvent(
            AutomationNotificationKind.Other,
            AutomationNotificationProcessing.MostRecent,
            spoken,
            "MiniXiangqi.Result");
    }

    private async void ShowAlert()
    {
        if (_play is not { } play || _showing != PlayAlert.None || play.Alert == PlayAlert.None)
        {
            return;
        }

        PlayAlert alert = play.Alert;
        _showing = alert;

        ContentDialog dialog = new()
        {
            XamlRoot = Root.XamlRoot,
            DefaultButton = ContentDialogButton.Primary,
        };

        switch (alert)
        {
            case PlayAlert.Resign:
                dialog.Title = Strings.Get("alert.resign.title");
                dialog.Content = Strings.Get("alert.resign.message");
                dialog.PrimaryButtonText = Strings.Get("control.resign");
                dialog.CloseButtonText = Strings.Get("control.cancel");

                // Nothing here is tinted: a destructive act does not get the
                // emphasis a wanted one gets, and the default is the way out
                // rather than the way through.
                dialog.DefaultButton = ContentDialogButton.Close;
                break;

            case PlayAlert.ClaimDraw:
                dialog.Title = Strings.Get("alert.claimDraw.title");
                dialog.Content = Strings.Get("alert.claimDraw.message");
                dialog.PrimaryButtonText = Strings.Get("control.endAsDraw");
                dialog.CloseButtonText = Strings.Get("control.keepPlaying");
                break;

            case PlayAlert.SaveFailed:
                dialog.Title = Strings.Get("alert.saveFailed.title");
                dialog.Content = Strings.Get("alert.saveFailed.message");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;

            default:
                // 无法启动 AI 对手, in its mid-game form: the situation is the
                // same one and keeps its title, and what this form adds is the
                // one thing the pre-start case has no need of — the game is
                // saved. Its actions are 稍后 and 重试, because there is nothing
                // to cancel.
                dialog.Title = Strings.Get("alert.aiUnavailable.title");
                dialog.Content = Strings.Get("alert.aiUnavailable.resumeMessage");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.later");
                break;
        }

        ContentDialogResult result = await dialog.ShowAsync();
        _showing = PlayAlert.None;
        if (play.Alert != alert)
        {
            return;
        }

        bool confirmed = result == ContentDialogResult.Primary;
        switch (alert)
        {
            case PlayAlert.Resign when confirmed:
                play.ConfirmResign();
                break;
            case PlayAlert.ClaimDraw when confirmed:
                play.ConfirmClaimDraw();
                break;
            case PlayAlert.SaveFailed when confirmed:
                play.RetryFailedCommit();
                break;
            case PlayAlert.EngineMemory when confirmed:
                play.RetryEngine();
                break;
            case PlayAlert.EngineMemory:
                play.DeferEngine();
                break;
            default:
                play.DismissAlert();
                break;
        }
    }

    private void ShowFailure(string titleKey, MxqException failure) =>
        ShowFailure(
            titleKey,
            $"{failure.StatusName} ({failure.Status}), domain {failure.Domain}\n{failure.Detail}");

    private void ShowFailure(string titleKey, string diagnostic)
    {
        // The title is copy; the description beneath it is diagnostic text and
        // is not localized.
        FailureTitle.Text = Strings.Get(titleKey);
        FailureDetail.Text = diagnostic;
        Failure.Visibility = Visibility.Visible;
        Notice.Visibility = Visibility.Collapsed;
        Panel.Visibility = Visibility.Collapsed;
        BoardHost.Visibility = Visibility.Collapsed;
    }

    /// <summary>
    /// The application's backstop, arriving here. Everything this repository
    /// knows how to be refused is answered where it happens; what reaches this
    /// is something nobody anticipated, so it stops the screen offering play and
    /// says what it was. The game itself is whole — the store commits every move
    /// inside its own call — and 对局未能开始 is the honest title for a screen
    /// that can no longer be played on.
    /// </summary>
    internal void ReportUnexpected(Exception failure) =>
        ShowFailure("failure.gameDidNotStart", $"{failure.GetType().Name}\n{failure.Message}");

    /// <summary>
    /// The window's thread, as the play session's scheduler. The search
    /// callback arrives on the core's engine thread and engine preparation runs
    /// on a pool thread; both come back through here before anything the
    /// interface reads is touched.
    /// </summary>
    private sealed class WindowScheduler(DispatcherQueue queue) : IPlayScheduler
    {
        public void Post(Action work) => queue.TryEnqueue(() => work());

        public IDisposable After(TimeSpan delay, Action work)
        {
            DispatcherQueueTimer timer = queue.CreateTimer();
            timer.Interval = delay;
            timer.IsRepeating = false;
            timer.Tick += (sender, _) =>
            {
                sender.Stop();
                work();
            };
            timer.Start();
            return new Token(timer);
        }

        private sealed class Token(DispatcherQueueTimer timer) : IDisposable
        {
            public void Dispose() => timer.Stop();
        }
    }
}
