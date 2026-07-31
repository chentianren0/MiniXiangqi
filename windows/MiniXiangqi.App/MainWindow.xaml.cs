// The Play destination on screen: the home, the two pre-start states, and the
// board.
//
// Everything below is presentation and wiring. Which page is showing, what a
// mode entry does, what 开始对局 creates and in which order, what a click on a
// point means, when the machine thinks and what happens when it answers all live
// in MiniXiangqi.Play — PlayFlow and PlaySession — which have no window and can
// therefore be run on a machine nobody is logged into. This file turns that
// state into XAML and turns XAML's events back into calls on it.
//
// **The temporary seam is gone.** Until this pull request the window resumed the
// single active game or created one exactly as the walking skeleton did — human
// versus AI, the human Red and moving first, at 快速 — with no way to choose.
// PlayFlow replaces the whole of that: a game is created by 开始对局 and by
// nothing else, and a launch with nothing to resume opens on the home.

using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;
using MiniXiangqi.Play;

namespace MiniXiangqi.App;

public sealed partial class MainWindow : Window
{
    /// <summary>
    /// The navigation row's height, which the window's own floor has to allow
    /// for on top of the board block and the air around it.
    /// </summary>
    private const double NavigationBarHeight = 44;

    private readonly BoardView _board = new();
    private readonly BoardView _preview = new(interactive: false);
    private readonly MiniXiangqiCore? _core;
    private readonly PlayFlow? _flow;

    /// <summary>
    /// Whether a <c>ContentDialog</c> is up. One at a time, because a
    /// <c>ContentDialog</c> is: a second <c>ShowAsync</c> over the same
    /// <c>XamlRoot</c> throws rather than queueing.
    /// </summary>
    private bool _dialogUp;

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

        PreviewHost.Children.Add(_preview);
        _preview.HorizontalAlignment = HorizontalAlignment.Center;
        _preview.VerticalAlignment = VerticalAlignment.Center;

        string assets = Path.Combine(AppContext.BaseDirectory, "assets");
        string store = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MiniXiangqi",
            "store");

        MiniXiangqiCore core;
        try
        {
            core = MiniXiangqiCore.Start(store, assets);
        }
        catch (MxqException failure)
        {
            ShowFailure("failure.coreDidNotStart", failure);
            return;
        }

        _core = core;
        PlayFlow flow = new(core, new WindowScheduler(DispatcherQueue));
        _flow = flow;
        flow.Changed += Refresh;

        try
        {
            // A resume, and only a resume: a launch with a game to open goes
            // straight to the board, and a launch with none opens on the home.
            flow.Start();
        }
        catch (MxqException failure)
        {
            ShowFailure("failure.gameDidNotStart", failure);
            return;
        }

        Closed += (_, _) =>
        {
            _board.Release();
            _preview.Release();
            _flow?.Dispose();
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
    /// Both the board and the chrome have floors, so the window has one too, and
    /// it stops resizing there rather than either becoming unusable. The board
    /// block at the accepted 44-point pitch is 340 square, the air around it is
    /// 24 a side, the panel beside it is 260, and the navigation row above every
    /// page is 44.
    ///
    /// It is the destination's floor rather than the board page's, and the same
    /// number on every page: a window that could be shrunk on the home and then
    /// walked to the board is a window that clips the board.
    /// </summary>
    private void StopShrinkingAtTheFloors(double scale)
    {
        if (AppWindow.Presenter is not Microsoft.UI.Windowing.OverlappedPresenter presenter)
        {
            return;
        }

        BoardGeometry floor = new(BoardGeometry.MinimumPitch);
        presenter.PreferredMinimumWidth = (int)Math.Ceiling((floor.BlockSide + 48 + 260) * scale);
        presenter.PreferredMinimumHeight =
            (int)Math.Ceiling((floor.BlockSide + 48 + NavigationBarHeight) * scale);
    }

    private void OnBoardHostSizeChanged(object sender, SizeChangedEventArgs args) =>
        Fit(_board, BoardHost, args.NewSize);

    private void OnPreviewHostSizeChanged(object sender, SizeChangedEventArgs args) =>
        Fit(_preview, PreviewHost, args.NewSize);

    private static void Fit(BoardView view, Grid host, Windows.Foundation.Size available)
    {
        // The board is square and is sized to the largest square fitting both
        // the available width and the height left after the surrounding chrome,
        // so it never overflows a short window.
        double side = Math.Min(
            available.Width - host.Padding.Left - host.Padding.Right,
            available.Height - host.Padding.Top - host.Padding.Bottom);
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
        view.Geometry = BoardGeometry.Fitting(side) ?? new BoardGeometry(BoardGeometry.MinimumPitch);
    }

    // The navigation row.

    private void OnBack(object sender, RoutedEventArgs args) => _flow?.LeaveTopPage();

    // The Play home.

    private void OnResume(object sender, RoutedEventArgs args) => _flow?.Resume();

    private void OnChooseHumanVersusAi(object sender, RoutedEventArgs args) =>
        _flow?.Choose(PlayMode.HumanVersusAi);

    private void OnChooseFreePlay(object sender, RoutedEventArgs args) =>
        _flow?.Choose(PlayMode.FreePlay);

    // The pre-start page.

    private void OnFirstMoverChanged(object sender, SelectionChangedEventArgs args) =>
        _flow?.ChooseFirstMover(FirstMover.SelectedIndex switch
        {
            1 => FirstMoverChoice.AiFirst,
            2 => FirstMoverChoice.Random,
            _ => FirstMoverChoice.HumanFirst,
        });

    private void OnLevelChanged(object sender, SelectionChangedEventArgs args) =>
        _flow?.ChooseLevel(Level.SelectedIndex switch
        {
            0 => AiLevel.Fast,
            2 => AiLevel.Deep,
            _ => AiLevel.Standard,
        });

    private void OnStartGame(object sender, RoutedEventArgs args) => _flow?.StartGame();

    // Board input.

    private void OnPointTapped(Square square)
    {
        if (Dismissed())
        {
            return;
        }

        _flow?.Session?.Tap(square);
    }

    private void OnBackgroundTapped()
    {
        if (Dismissed())
        {
            return;
        }

        _flow?.Session?.CancelSelection();
    }

    private void OnPointerOver(Square? square) => _flow?.Session?.Hover(square);

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
        if (_flow?.Session is not { } play || play.Notice == ResultNotice.None)
        {
            return false;
        }

        play.DismissNotice();
        return true;
    }

    // Play controls. What the cluster carries is the mode's, and while a game is
    // finished there is no draw left to judge, so that slot carries the
    // concluding action instead.

    private void OnUndo(object sender, RoutedEventArgs args) => _flow?.Session?.Undo();

    private void OnMiddle(object sender, RoutedEventArgs args)
    {
        if (_flow?.Session is not { } play)
        {
            return;
        }

        if (play.IsOver)
        {
            // 开始新对局 files the finished game and opens that game's own
            // mode's pre-start state, which is the destination's to do.
            _flow.StartNewGame();
        }
        else
        {
            play.RequestClaimDraw();
        }
    }

    private void OnTrailing(object sender, RoutedEventArgs args)
    {
        if (_flow?.Session is not { } play)
        {
            return;
        }

        if (play.CanFlip)
        {
            play.FlipBoard();
        }
        else
        {
            play.RequestResign();
        }
    }

    private void OnRetryEngine(object sender, RoutedEventArgs args) => _flow?.Session?.RetryEngine();

    private void OnDismissNotice(object sender, RoutedEventArgs args) =>
        _flow?.Session?.DismissNotice();

    private void OnNoticePrimary(object sender, RoutedEventArgs args)
    {
        if (_flow?.Session is not { } play)
        {
            return;
        }

        if (play.Notice == ResultNotice.Recorded)
        {
            // 完成 returns to the Play home, where what to play is chosen again.
            _flow.Finish();
        }
        else
        {
            play.SaveResult();
        }
    }

    private void OnNoticeSecondary(object sender, RoutedEventArgs args) => _flow?.StartNewGame();

    // Presentation.

    private void Refresh()
    {
        if (_flow is not { } flow)
        {
            return;
        }

        ShowPage(flow);
        switch (flow.Page)
        {
            case PlayPage.Home:
                ShowHome(flow);
                break;
            case PlayPage.Setup:
                ShowSetup(flow);
                break;
            case PlayPage.Board when flow.Session is { } play:
                ShowBoard(play);
                break;
        }

        ShowDialog(flow);
    }

    private void ShowPage(PlayFlow flow)
    {
        HomePage.Visibility = Shown(flow.Page == PlayPage.Home);
        SetupPage.Visibility = Shown(flow.Page == PlayPage.Setup);
        BoardPage.Visibility = Shown(flow.Page == PlayPage.Board && flow.Session is not null);

        // The back control appears on the two pages that have somewhere to go
        // back to, and names the page it returns to — which here is always the
        // Play home. The title is the destination's rather than any one page's,
        // because all three pages carry the same one.
        Back.Visibility = Shown(flow.Page != PlayPage.Home);
        AutomationProperties.SetName(Back, Strings.Get("nav.play"));
        PageTitle.Text = Strings.Get("nav.play");
    }

    private void ShowHome(PlayFlow flow)
    {
        bool active = flow.ActiveGameLine is { Length: > 0 };
        CurrentGame.Visibility = Shown(active);
        CurrentGameHeader.Text = Strings.Get("alert.newGame.metadataHeader");
        CurrentGameLine.Text = flow.ActiveGameLine ?? string.Empty;
        ResumeGame.Content = Strings.Get("nav.resumeGame");

        // Both mode entries remain interactive whenever a game is active:
        // selecting one presents the accepted confirmation rather than opening
        // anything.
        ModeEntry(ModeHumanVersusAi, "mode.humanVersusAI");
        ModeEntry(ModeFreePlay, "mode.freePlay");
    }

    /// <summary>
    /// One way to play: its name, and the chevron that says choosing it opens a
    /// page rather than dealing a game.
    /// </summary>
    private static void ModeEntry(Button entry, string key)
    {
        string title = Strings.Get(key);
        AutomationProperties.SetName(entry, title);
        entry.Content = new Grid
        {
            ColumnDefinitions =
            {
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) },
                new ColumnDefinition { Width = GridLength.Auto },
            },
            Children =
            {
                new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center },
                Chevron(),
            },
        };
    }

    private static TextBlock Chevron()
    {
        TextBlock chevron = new()
        {
            Text = "\uE76C", // ChevronRight, from the system's own symbol font.
            FontFamily = (FontFamily)Application.Current.Resources["SymbolThemeFontFamily"],
            FontSize = 12,
            Opacity = 0.6,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(chevron, 1);
        return chevron;
    }

    private void ShowSetup(PlayFlow flow)
    {
        _preview.Scene = flow.PreviewScene;

        bool versusAi = flow.SetupMode == PlayMode.HumanVersusAi;
        ThisGame.Visibility = Shown(versusAi);
        FreePlayExplanation.Visibility = Shown(!versusAi);
        FreePlayExplanation.Text = Strings.Get("setup.freePlayExplanation");

        ThisGameHeader.Text = Strings.Get("setup.thisGame");

        // 本局设置 names the group and the three options name themselves, so
        // 先后手 is not drawn; a screen reader still has to be able to call the
        // control something.
        AutomationProperties.SetName(FirstMover, Strings.Get("setup.firstMover"));
        FirstMoverHuman.Content = Strings.Get("setup.iMoveFirst");
        FirstMoverAi.Content = Strings.Get("setup.aiMovesFirst");
        FirstMoverRandom.Content = Strings.Get("setup.random");
        FirstMover.SelectedIndex = flow.Draft.FirstMover switch
        {
            FirstMoverChoice.AiFirst => 1,
            FirstMoverChoice.Random => 2,
            _ => 0,
        };

        Level.Header = Strings.Get("setup.aiLevel");
        AutomationProperties.SetName(Level, Strings.Get("setup.aiLevel"));
        LevelFast.Content = Strings.Get("setup.level.fast");
        LevelStandard.Content = Strings.Get("setup.level.standard");
        LevelDeep.Content = Strings.Get("setup.level.deep");
        Level.SelectedIndex = flow.Draft.Level switch
        {
            AiLevel.Fast => 0,
            AiLevel.Deep => 2,
            _ => 1,
        };

        StartGame.Content = Strings.Get("control.startGame");
        StartGame.IsEnabled = !flow.Creating;
    }

    private void ShowBoard(PlaySession play)
    {
        _board.Scene = play.Scene;

        StatusPrimary.Text = play.PrimaryStatus();
        StatusSecondary.Text = play.SecondaryStatus() ?? string.Empty;
        StatusSecondary.Visibility = Shown(StatusSecondary.Text.Length > 0);

        bool thinking = play.Activity == AiActivity.Thinking;
        Thinking.IsActive = thinking;
        Thinking.Visibility = Shown(thinking);
        AutomationProperties.SetName(Thinking, Strings.Get("status.aiThinking"));

        Stalled.Visibility = Shown(play.Activity == AiActivity.Stalled);
        StalledText.Text = Strings.Get("status.aiUnavailable");
        StalledRetry.Content = Strings.Get("control.tryAgain");

        SaveFailure.Visibility = Shown(play.MoveNotSaved);
        SaveFailureText.Text = Strings.Get("status.saveFailed");

        ShowControls(play);
        ShowRecord(play);
        ShowNotice(play);
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
            Trailing.Visibility = Shown(!play.IsOver);
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
            FontFamily = new FontFamily("Consolas"),
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
        NoticeReason.Visibility = Shown(NoticeReason.Text.Length > 0);

        // Before confirmation both actions save, and the default one only
        // saves: when a game ends, keeping the game that was just played is
        // wanted far more often than being dealt the next one. Once recorded,
        // 完成 stands alone — 回放 opens a History record, and History arrives
        // with the pull request that builds it.
        NoticePrimary.Content = Strings.Get(recorded ? "control.done" : "control.save");
        NoticeSecondary.Content = Strings.Get("control.saveAndNewGame");
        NoticeSecondary.Visibility = Shown(!recorded);

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

    // The alerts. A confirmation of a consequential act is a system alert,
    // presented wherever the platform puts one and blocking until it is
    // answered, because the act itself does not happen until the player answers.
    //
    // One at a time, because a ContentDialog is: the destination's own alerts
    // take precedence, and the board's are presented only while the board is the
    // page. A mid-game engine failure that arrives while the player is on the
    // home therefore waits for them to come back to the board, which is where
    // its stalled state and its retry live anyway.

    private void ShowDialog(PlayFlow flow)
    {
        if (_dialogUp)
        {
            return;
        }

        if (flow.Alert != FlowAlert.None)
        {
            ShowFlowAlert(flow, flow.Alert);
        }
        else if (flow.Page == PlayPage.Board && flow.Session is { Alert: not PlayAlert.None } play)
        {
            ShowPlayAlert(play, play.Alert);
        }
    }

    private async void ShowFlowAlert(PlayFlow flow, FlowAlert alert)
    {
        _dialogUp = true;

        ContentDialog dialog = new()
        {
            XamlRoot = Root.XamlRoot,
            DefaultButton = ContentDialogButton.Primary,
        };

        switch (alert)
        {
            case FlowAlert.NewGame:
                // The one fixed confirmation for every combination of old mode,
                // new mode and active-game state. Only the metadata changes; the
                // title, message and actions interpolate nothing.
                //
                // The metadata header and the metadata line ride in the content,
                // separated from the sentence by a blank line and by nothing
                // else: a line break carries no punctuation and is the same in
                // both languages, so no format string stands between them.
                dialog.Title = Strings.Get("alert.newGame.title");
                dialog.Content = string.Join(
                    '\n',
                    Strings.Get("alert.newGame.metadataHeader"),
                    flow.ActiveGameLine ?? string.Empty,
                    string.Empty,
                    Strings.Get("alert.newGame.message"));
                dialog.PrimaryButtonText = Strings.Get("control.saveAndContinue");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;

            case FlowAlert.ArchiveFailed:
                dialog.Title = Strings.Get("alert.saveFailed.title");
                dialog.Content = Strings.Get("alert.saveFailed.message");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;

            case FlowAlert.AiUnavailable:
                // 无法启动 AI 对手 in its pre-start form: no game exists, so the
                // message carries no saved-game guarantee and the way out is
                // 取消 rather than 稍后.
                dialog.Title = Strings.Get("alert.aiUnavailable.title");
                dialog.Content = Strings.Get("alert.aiUnavailable.message");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;

            default:
                dialog.Title = Strings.Get("alert.gameNotStarted.title");
                dialog.Content = Strings.Get("alert.gameNotStarted.message");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;
        }

        ContentDialogResult result = await dialog.ShowAsync();
        _dialogUp = false;
        if (flow.Alert != alert)
        {
            // The situation moved on while the player was reading. Whatever
            // replaced it will present itself; this answer is about a question
            // that is no longer being asked.
            return;
        }

        bool confirmed = result == ContentDialogResult.Primary;
        switch (alert)
        {
            case FlowAlert.NewGame when confirmed:
            case FlowAlert.ArchiveFailed when confirmed:
                // 重试 repeats exactly the same atomic archive rather than
                // something near it.
                flow.SaveAndContinue();
                break;
            case FlowAlert.AiUnavailable when confirmed:
            case FlowAlert.GameNotStarted when confirmed:
                // The page and the draft are still there, and 重试 repeats the
                // whole attempt, probe and all.
                flow.StartGame();
                break;
            default:
                flow.DismissAlert();
                break;
        }
    }

    private async void ShowPlayAlert(PlaySession play, PlayAlert alert)
    {
        _dialogUp = true;

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
        _dialogUp = false;
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

    private static Visibility Shown(bool shown) =>
        shown ? Visibility.Visible : Visibility.Collapsed;

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
        HomePage.Visibility = Visibility.Collapsed;
        SetupPage.Visibility = Visibility.Collapsed;
        BoardPage.Visibility = Visibility.Collapsed;
        Back.Visibility = Visibility.Collapsed;
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
