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
using Windows.Foundation;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace MiniXiangqi.App;

public sealed partial class MainWindow : Window
{
    private readonly BoardView _board = new();
    private readonly BoardView _preview = new(interactive: false);

    /// <summary>
    /// The viewer's board: noninteractive, exactly as the pre-start preview is.
    /// Replay is read-only — it offers no move input, no Undo, and no way to
    /// start a game from the displayed position — so it has no points for a
    /// pointer to hit or a screen reader to offer.
    /// </summary>
    private readonly BoardView _replayBoard = new(interactive: false);

    /// <summary>
    /// The line each board host shows when it has no room for a board, one per
    /// host so that each says it in its own space.
    ///
    /// They are built here rather than in the XAML for the same reason the three
    /// boards above are: what a host contains is this file's business, the three
    /// are identical, and three copies of the same block of markup is three
    /// places for them to stop being identical.
    /// </summary>
    private readonly TextBlock _boardTooSmall = TooSmall("board-too-small");
    private readonly TextBlock _previewTooSmall = TooSmall("preview-too-small");
    private readonly TextBlock _replayTooSmall = TooSmall("replay-too-small");

    private readonly MiniXiangqiCore? _core;
    private readonly PlayFlow? _flow;
    private readonly HistoryFlow? _history;
    private readonly SettingsScreen? _settings;

    /// <summary>
    /// The four voices, primed at this window's construction so that the first
    /// tock is no later than the second. It is built whether or not a game is
    /// ever played: four small buffers is less than the first landing would cost
    /// to read them.
    /// </summary>
    private readonly BoardSoundPlayer _sounds = new();

    /// <summary>
    /// The system's own accessibility and appearance settings, of which this
    /// window reads one: whether animations are wanted.
    /// </summary>
    private readonly Windows.UI.ViewManagement.UISettings _system = new();

    /// <summary>The shell's three top-level destinations.</summary>
    private enum Destination
    {
        Play,
        History,
        Settings,
    }

    /// <summary>Which top-level destination the shell is showing.</summary>
    private Destination _destination = Destination.Play;

    /// <summary>
    /// The History state this window has already drawn rows for.
    ///
    /// Everything on either destination publishes through one event — including
    /// the play session's own thinking indicator, which ticks while a search runs
    /// — and rebuilding a list of rows in answer to something that happened on
    /// the other destination is the class of waste the play screen's move record
    /// already guards against. So the rows are rebuilt when History changed and
    /// not otherwise.
    /// </summary>
    private int _renderedHistory = -1;

    /// <summary>Whether the window is showing a failure it cannot come back from.</summary>
    private bool _fatal;

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
        WearTheIcon();
        Root.Loaded += (_, _) => WatchTheScale();

        BoardHost.Children.Add(_board);
        BoardHost.Children.Add(_boardTooSmall);
        _board.HorizontalAlignment = HorizontalAlignment.Center;
        _board.VerticalAlignment = VerticalAlignment.Center;
        _board.PointTapped += OnPointTapped;
        _board.BackgroundTapped += OnBackgroundTapped;
        _board.PointerOverChanged += OnPointerOver;
        Root.KeyDown += OnKeyDown;

        PreviewHost.Children.Add(_preview);
        PreviewHost.Children.Add(_previewTooSmall);
        _preview.HorizontalAlignment = HorizontalAlignment.Center;
        _preview.VerticalAlignment = VerticalAlignment.Center;

        ReplayHost.Children.Add(_replayBoard);
        ReplayHost.Children.Add(_replayTooSmall);
        _replayBoard.HorizontalAlignment = HorizontalAlignment.Center;
        _replayBoard.VerticalAlignment = VerticalAlignment.Center;

        DestinationPlay.Content = Strings.Get("nav.play");
        DestinationHistory.Content = Strings.Get("nav.history");
        Shell.SelectedItem = DestinationPlay;

        // The container's own settings item is realized when its template is
        // applied, which has not happened yet in a constructor — so the one thing
        // the app supplies about it, its word, is supplied when it exists. If it
        // somehow does not, the framework's own word stands and the destination
        // still works; a missing label is not worth a launch failure.
        Shell.Loaded += (_, _) =>
        {
            if (Shell.SettingsItem is NavigationViewItem item)
            {
                item.Content = Strings.Get("nav.settings");
            }
        };

        string assets = Path.Combine(AppContext.BaseDirectory, "assets");
        string preferences = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MiniXiangqi",
            "preferences.json");
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
            ShowFatalFailure("failure.coreDidNotStart", failure);
            return;
        }

        _core = core;
        WindowScheduler scheduler = new(DispatcherQueue);

        // One store for all three destinations, so that a preference the Settings
        // screen writes is the same preference the pre-start page, the deletion
        // gate and the sound gate read — and so that "read at the moment of use"
        // is one file's behaviour rather than three objects' agreement. The path
        // is named here rather than left to the parameterless constructor because
        // it is this window that decides where this app keeps things.
        FilePreferenceStore stored = new(preferences);

        PlayFlow flow = new(
            core,
            scheduler,
            stored,
            probe: null,
            feedback: Feedback.Gating(stored, _sounds.Play));
        _flow = flow;
        flow.Changed += Refresh;

        // The History destination is built now and read when it is first shown:
        // its list is two store queries and there is no reason to make them at
        // launch, when the app opens on the board or on the Play home.
        HistoryFlow history = new(core, scheduler, stored);
        _history = history;
        history.Changed += Refresh;

        // Settings holds no state of its own beyond the file, so it is built here
        // and never reloaded: every value it shows is read from the store as it
        // draws.
        SettingsScreen settings = new(stored);
        _settings = settings;
        settings.Changed += Refresh;

        try
        {
            // A resume, and only a resume: a launch with a game to open goes
            // straight to the board, and a launch with none opens on the home.
            flow.Start();
        }
        catch (MxqException failure)
        {
            ShowFatalFailure("failure.gameDidNotStart", failure);
            return;
        }

        Closed += (_, _) =>
        {
            _board.Release();
            _preview.Release();
            _replayBoard.Release();

            // Both destinations are quiesced before the core is shut down: each
            // has calls it started that may still be inside it, and the core does
            // not defend against a caller that has not quiesced its own threads.
            _history?.Dispose();
            _flow?.Dispose();
            _core?.Dispose();
        };
    }

    /// <summary>
    /// The title bar's icon, and with it the taskbar's.
    ///
    /// <c>ApplicationIcon</c> in the project file puts <c>MiniXiangqi.ico</c> in
    /// the executable's resources, which is what Explorer, a shortcut and the
    /// unpacked zip's folder show. That is a different question from what the
    /// running window wears: a WinUI 3 window's icon is the <c>AppWindow</c>'s,
    /// and for an unpackaged app there is no package manifest to declare it in,
    /// so it is set here. The same file answers both, so the two can never show
    /// different pictures.
    ///
    /// <c>SetIcon(string)</c> takes a path, which means the file has to be beside
    /// the executable; the project copies it there and the distribution zip
    /// carries it. If it is not there, the window keeps the framework's default
    /// icon and everything else works — a picture is not worth a launch failure,
    /// which is the same rule the settings item's label is under above.
    /// </summary>
    private void WearTheIcon()
    {
        try
        {
            string icon = Path.Combine(AppContext.BaseDirectory, "MiniXiangqi.ico");
            if (File.Exists(icon))
            {
                AppWindow.SetIcon(icon);
            }
        }
        catch (Exception)
        {
            // Every failure here is cosmetic by construction.
        }
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
    /// it stops resizing there rather than either becoming unusable. Every
    /// figure is <see cref="WindowFloor"/>'s, derived from the board's own
    /// geometry — 696 by 432 at a scale of 1, in device-independent pixels — and
    /// two things are added to it here, because both are properties of this
    /// window rather than of the layout.
    ///
    /// **The display scale**, because the two sides of the sum are measured in
    /// different units, which the comment on <see cref="WatchTheScale"/>
    /// explains.
    ///
    /// **The frame**, because <c>PreferredMinimumWidth</c> answers
    /// <c>WM_GETMINMAXINFO</c>, and that message is about the *window* rectangle
    /// — the resize borders and the title bar included — while everything XAML
    /// lays out is inside the client area. A floor set from the content alone is
    /// therefore short by exactly the frame, and short in the direction that
    /// matters: the window stops shrinking while the board still has less room
    /// than its floor asks for. The frame is measured rather than assumed —
    /// <c>AppWindow.Size</c> is documented as including the non-client area and
    /// <c>ClientSize</c> as excluding it, both in physical pixels, so their
    /// difference is the frame in the units this property wants. It is read on
    /// every recomputation because it moves with the scale.
    ///
    /// It is the app's floor rather than any one page's, and the same number
    /// everywhere: a window that could be shrunk on the History list and then
    /// walked to the board is a window that clips the board.
    /// </summary>
    private void StopShrinkingAtTheFloors(double scale)
    {
        if (AppWindow.Presenter is not Microsoft.UI.Windowing.OverlappedPresenter presenter)
        {
            return;
        }

        double frameWidth = Math.Max(0, AppWindow.Size.Width - AppWindow.ClientSize.Width);
        double frameHeight = Math.Max(0, AppWindow.Size.Height - AppWindow.ClientSize.Height);

        presenter.PreferredMinimumWidth =
            (int)Math.Ceiling((WindowFloor.WindowWidth * scale) + frameWidth);
        presenter.PreferredMinimumHeight =
            (int)Math.Ceiling((WindowFloor.WindowHeight * scale) + frameHeight);
    }

    private void OnBoardHostSizeChanged(object sender, SizeChangedEventArgs args) =>
        Fit(_board, BoardHost, _boardTooSmall, args.NewSize);

    private void OnPreviewHostSizeChanged(object sender, SizeChangedEventArgs args) =>
        Fit(_preview, PreviewHost, _previewTooSmall, args.NewSize);

    private void OnReplayHostSizeChanged(object sender, SizeChangedEventArgs args) =>
        Fit(_replayBoard, ReplayHost, _replayTooSmall, args.NewSize);

    /// <summary>
    /// A host, and what it shows for the room it has.
    ///
    /// The decision is <see cref="BoardSpace"/>'s, where a headless run can reach
    /// it; what is left here is turning it into two visibilities. **The refusal
    /// is now visible**, which is the owner's tour finding: the geometry has
    /// always declined to draw a board under the accepted floor, and this window
    /// used to answer that by drawing one at the floor anyway, into a host too
    /// small to hold it. The board is not drawn, and the line that asks for a
    /// larger window is, in the space the board would have taken.
    ///
    /// All three hosts, including the pre-start preview. The contract exempts a
    /// preview from the floor so that it can yield space to the setup controls;
    /// on this frontend those controls are a fixed 260-point panel that never
    /// asks for more, so there is nothing for the preview to yield to and it has
    /// taken the same floor as the other two since the play screen landed. A
    /// preview with no room is the same silent emptiness, and it says the same
    /// thing.
    /// </summary>
    private static void Fit(BoardView view, Grid host, TextBlock notice, Windows.Foundation.Size available)
    {
        BoardSpace space = BoardSpace.Of(
            available.Width - host.Padding.Left - host.Padding.Right,
            available.Height - host.Padding.Top - host.Padding.Bottom);

        if (space.Board is { } fitted)
        {
            view.Geometry = fitted;
        }

        view.Visibility = Shown(space.ShowsBoard);
        notice.Text = space.Notice ?? string.Empty;
        notice.Visibility = Shown(!space.ShowsBoard);
    }

    /// <summary>
    /// The line a board host shows in the board's place. Centred in the space
    /// the board would have taken, wrapping rather than truncating — it is a
    /// sentence and both of its halves matter — and quiet, because nothing has
    /// gone wrong.
    /// </summary>
    private static TextBlock TooSmall(string automationId)
    {
        TextBlock line = new()
        {
            Visibility = Visibility.Collapsed,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 280,
        };

        if (Application.Current.Resources.TryGetValue("BodyTextBlockStyle", out object? body)
            && body is Style style)
        {
            line.Style = style;
        }

        if (SystemBrush("TextFillColorSecondaryBrush") is { } secondary)
        {
            line.Foreground = secondary;
        }

        AutomationProperties.SetAutomationId(line, automationId);
        return line;
    }

    // The shell, and the navigation row inside it.

    /// <summary>
    /// A top-level destination was chosen. Nothing is created, released or
    /// committed: the game stays active whichever destination is on screen, and
    /// each destination's own state is exactly where it was left.
    /// </summary>
    private void OnDestinationChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        // The settings item is the container's own rather than one of the menu
        // items, so it is what `IsSettingsSelected` reports rather than something
        // to compare against.
        _destination = args.IsSettingsSelected ? Destination.Settings
            : ReferenceEquals(args.SelectedItem, DestinationHistory) ? Destination.History
            : Destination.Play;

        // The library is read when the destination is first shown, and re-read on
        // every later visit — a game finished on the Play destination is a new
        // row, and the revision check makes the re-read two cheap queries when
        // nothing changed.
        if (_destination == Destination.History)
        {
            _history?.LoadIfChanged();
        }

        Refresh();
    }

    private void OnBack(object sender, RoutedEventArgs args)
    {
        // Settings has one page and no back control, so it never reaches here.
        if (_destination == Destination.History)
        {
            _history?.CloseViewer();
        }
        else if (_destination == Destination.Play)
        {
            _flow?.LeaveTopPage();
        }
    }

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

    // Settings. Every control writes as it changes: a preference screen has no
    // Save button, and the next landing or the next deletion is entitled to the
    // new answer rather than to the one the app launched with.
    //
    // Each handler also fires when a refresh *sets* its control, which is what a
    // XAML selector does when it is given a value. SettingsScreen writes nothing
    // when the value it is handed is the value already stored, so a redraw is not
    // a write and cannot loop through Changed.

    private void OnDefaultFirstMoverChanged(object sender, SelectionChangedEventArgs args) =>
        _settings?.ChooseDefaultFirstMover(DefaultFirstMover.SelectedIndex switch
        {
            1 => FirstMoverChoice.AiFirst,
            2 => FirstMoverChoice.Random,
            _ => FirstMoverChoice.HumanFirst,
        });

    private void OnDefaultAiLevelChanged(object sender, SelectionChangedEventArgs args) =>
        _settings?.ChooseDefaultAiLevel(DefaultAiLevel.SelectedIndex switch
        {
            0 => AiLevel.Fast,
            2 => AiLevel.Deep,
            _ => AiLevel.Standard,
        });

    private void OnSoundToggled(object sender, RoutedEventArgs args) =>
        _settings?.SetSound(Sound.IsOn);

    private void OnConfirmDeleteToggled(object sender, RoutedEventArgs args) =>
        _settings?.SetDeleteConfirmation(ConfirmDelete.IsOn);

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

    private void OnTrailing(object sender, RoutedEventArgs args) => _flow?.Session?.RequestResign();

    private void OnFlip(object sender, RoutedEventArgs args) => _flow?.Session?.FlipBoard();

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

    /// <summary>
    /// The notice's second action, which is a different act on either side of
    /// confirmation: 保存并开始新对局 before it, and 回放 after.
    /// </summary>
    private void OnNoticeSecondary(object sender, RoutedEventArgs args)
    {
        if (_flow?.Session is not { } play)
        {
            return;
        }

        if (play.Notice != ResultNotice.Recorded)
        {
            _flow.StartNewGame();
            return;
        }

        // 回放 opens the record this game became, on the History destination
        // where every replay lives. The board it leaves behind is a finished
        // game's, and the game is filed, so nothing is lost by walking away from
        // it.
        if (play.FiledRecordId is { } record && _history is { } history)
        {
            play.DismissNotice();
            Shell.SelectedItem = DestinationHistory;
            history.Open(record);
        }
    }

    // History.

    private void OnRecordClicked(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is ListViewItem { Tag: ulong recordId })
        {
            _history?.Open(recordId);
        }
    }

    private void OnReplayFirst(object sender, RoutedEventArgs args) =>
        _history?.Step(viewer => viewer.First());

    private void OnReplayPrevious(object sender, RoutedEventArgs args) =>
        _history?.Step(viewer => viewer.Previous());

    private void OnReplayNext(object sender, RoutedEventArgs args) =>
        _history?.Step(viewer => viewer.Next());

    private void OnReplayLast(object sender, RoutedEventArgs args) =>
        _history?.Step(viewer => viewer.Last());

    private void OnReplayFlip(object sender, RoutedEventArgs args) =>
        _history?.Step(viewer => viewer.FlipBoard());

    /// <summary>
    /// 导入… — the picker allows exactly one file and filters to the declared
    /// game type, which is where the one-file-at-a-time rule is kept rather than
    /// where it is enforced by refusal.
    ///
    /// The bytes are read inside the grant the picker gave and no reference to
    /// the file is kept afterwards, which is the posture this repository's rules
    /// ask of an untrusted input; the size gate and everything the core answers
    /// belong to <see cref="HistoryFlow"/>, where they can be run without a
    /// window. **The picker itself is the part that cannot**: it needs the
    /// window's own handle, so it is the one step of the import path the headless
    /// harness stands in for by naming a file directly.
    /// </summary>
    private async void OnImport(object sender, RoutedEventArgs args)
    {
        if (_history is not { Transferring: false } history || _dialogUp)
        {
            return;
        }

        FileOpenPicker picker = new();
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        picker.FileTypeFilter.Add(".mxq");

        StorageFile? file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            history.ImportFile(file.Path);
        }
    }

    /// <summary>
    /// 共享 — one History record written out as one game file.
    ///
    /// **On Windows that is a Save As rather than a share sheet, and the reason
    /// is the accepted clause's own.** 共享 exports "through the platform's own
    /// sharing, over a file rather than over data alone: the services an offline
    /// team actually moves a game with — AirDrop, Mail, Messages — appear only
    /// for a file." Windows' `DataTransferManager` share UI reaches installed
    /// share targets and is not where a Windows user goes to hand somebody a
    /// file; its own conventional equivalent is to write the file and then send
    /// it, which is what docs/interaction-design.md § Platform adaptation
    /// requires — "where a platform lacks an interaction idiom used elsewhere …
    /// the same operations must be exposed through that platform's conventional
    /// equivalents". The file, its bytes, its name and its extension are
    /// identical either way, which is the part the interchange promise is about.
    /// </summary>
    private async void OnShare(ulong recordId, string suggested)
    {
        // Not while one is already in flight. `ExportTo` refuses a second
        // transfer, and without this the picker would open, take a filename, and
        // then write nothing to it.
        if (_history is not { Transferring: false } history)
        {
            return;
        }

        FileSavePicker picker = new();
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

        // The type's own name in the dialog's dropdown is the application's,
        // which is the one name this file format has that is already copy.
        picker.FileTypeChoices.Add(Strings.Get("app.displayName"), [".mxq"]);
        picker.SuggestedFileName = Path.GetFileNameWithoutExtension(suggested);

        StorageFile? file = await picker.PickSaveFileAsync();
        if (file is not null)
        {
            history.ExportTo(recordId, file.Path);
        }
    }

    // Presentation.

    private void Refresh()
    {
        if (_fatal || _flow is not { } flow || _history is not { } history)
        {
            return;
        }

        ShowPage(flow, history);
        switch (_destination)
        {
            case Destination.History when history.Page == HistoryPageKind.Viewer
                && history.Viewer is { } viewer:
                ShowViewer(viewer);
                break;

            case Destination.History:
                ShowHistory(history);
                break;

            case Destination.Settings when _settings is { } settings:
                ShowSettings(settings);
                break;

            case Destination.Play:
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

                break;
        }

        ShowDialog(flow, history);
    }

    private void ShowPage(PlayFlow flow, HistoryFlow history)
    {
        bool onHistory = _destination == Destination.History;
        bool onPlay = _destination == Destination.Play;
        bool viewing = onHistory && history.Page == HistoryPageKind.Viewer && history.Viewer is not null;
        bool listing = onHistory && !viewing;

        HomePage.Visibility = Shown(onPlay && flow.Page == PlayPage.Home);
        SetupPage.Visibility = Shown(onPlay && flow.Page == PlayPage.Setup);
        BoardPage.Visibility =
            Shown(onPlay && flow.Page == PlayPage.Board && flow.Session is not null);
        HistoryPage.Visibility = Shown(listing && history.LoadFailure is null);
        ViewerPage.Visibility = Shown(viewing);
        SettingsPage.Visibility = Shown(_destination == Destination.Settings);

        // A library that cannot be read says *that*, in the failure-screen
        // family, rather than showing an empty list it has no evidence for. It is
        // the History destination's own screen, so leaving the destination puts
        // it away.
        if (listing && history.LoadFailure is { } unread)
        {
            ShowFailure("failure.historyDidNotLoad", unread);
        }
        else
        {
            Failure.Visibility = Visibility.Collapsed;
        }

        // The back control appears on the pages that have somewhere to go back
        // to, and names the page it returns to. The title is the destination's
        // rather than any one page's, because its pages carry the same one —
        // Settings having exactly one, and no back control, because there is
        // nowhere under it to be.
        string destination = Strings.Get(_destination switch
        {
            Destination.History => "nav.history",
            Destination.Settings => "nav.settings",
            _ => "nav.play",
        });
        Back.Visibility = Shown(onHistory ? viewing : onPlay && flow.Page != PlayPage.Home);
        AutomationProperties.SetName(Back, destination);
        PageTitle.Text = destination;
    }

    /// <summary>
    /// The list of filed games: two sections, or one unheaded one, or the empty
    /// state.
    /// </summary>
    private void ShowHistory(HistoryFlow history)
    {
        Import.Content = Strings.Get("control.import");

        HistoryEmpty.Visibility = Shown(history.IsEmpty);
        HistoryEmptyTitle.Text = Strings.Get("history.empty.title");
        HistoryEmptyDescription.Text = Strings.Get("history.empty.description");

        // With nothing pinned there is one unheaded section and the list reads as
        // a plain list of games; a header naming the only group on the screen
        // labels the obvious.
        bool sectioned = history.PinnedCount > 0;
        PinnedHeader.Text = Strings.Get("history.section.pinned");
        OthersHeader.Text = Strings.Get("history.section.others");
        PinnedHeader.Visibility = Shown(sectioned);
        OthersHeader.Visibility = Shown(sectioned && history.PinnedCount < history.Records.Count);

        // The rows themselves are rebuilt only when this destination changed. A
        // search finishing on the other one publishes through the same event, and
        // a list of rows torn down and rebuilt because the AI moved is a list a
        // reader cannot keep their place in.
        if (_renderedHistory == history.Revision)
        {
            return;
        }

        _renderedHistory = history.Revision;
        Fill(PinnedRecords, history.Pinned, history);
        Fill(OtherRecords, history.Others, history);

        if (history.Highlighted is { } added)
        {
            ScrollToRow(added);
        }
    }

    /// <summary>
    /// One section's rows. Each is the record's two lines and the context menu
    /// that carries its actions — which on Windows is the primary path to them,
    /// as the contract says of this platform.
    /// </summary>
    private void Fill(ListView list, IEnumerable<RecordSummary> records, HistoryFlow history)
    {
        list.Items.Clear();
        foreach (RecordSummary record in records)
        {
            list.Items.Add(Row(record, history));
        }

        list.Visibility = Shown(list.Items.Count > 0);
    }

    private ListViewItem Row(RecordSummary record, HistoryFlow history)
    {
        TextBlock when = new()
        {
            Text = record.WhenLine(),
            TextWrapping = TextWrapping.Wrap,
        };

        // Every token on the second line is content the contract asks for, so it
        // wraps rather than truncating.
        TextBlock metadata = new()
        {
            Text = record.MetadataLine(),
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            TextWrapping = TextWrapping.Wrap,
        };

        if (SystemBrush("TextFillColorSecondaryBrush") is { } secondary)
        {
            metadata.Foreground = secondary;
        }

        // **Action meaning is carried by icon and text as well as colour**, which
        // is the accepted rule for these three and the reason each one below has
        // a symbol beside its word rather than only a word.
        MenuFlyout actions = new();
        MenuFlyoutItem pin = new()
        {
            Text = Strings.Get(record.Pinned ? "control.unpin" : "control.pin"),
            Icon = new SymbolIcon(record.Pinned ? Symbol.UnPin : Symbol.Pin),
        };
        pin.Click += (_, _) => history.SetPinned(record.RecordId, !record.Pinned);
        actions.Items.Add(pin);

        MenuFlyoutItem share = new()
        {
            Text = Strings.Get("control.share"),
            Icon = new SymbolIcon(Symbol.Share),
        };
        share.Click += (_, _) => OnShare(record.RecordId, record.SuggestedFileName());
        actions.Items.Add(share);

        actions.Items.Add(new MenuFlyoutSeparator());

        // The destructive action takes the system's own destructive colour rather
        // than a tint this file chose, so red keeps one meaning. Its icon and its
        // word carry the meaning besides, which is why the colour can be absent
        // without the action becoming ambiguous.
        MenuFlyoutItem delete = new()
        {
            Text = Strings.Get("control.delete"),
            Icon = new SymbolIcon(Symbol.Delete),
        };
        if (SystemBrush("SystemFillColorCriticalBrush") is { } critical)
        {
            delete.Foreground = critical;
        }

        delete.Click += (_, _) => history.RequestDelete(record.RecordId);
        actions.Items.Add(delete);

        ListViewItem row = new()
        {
            Tag = record.RecordId,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Content = new StackPanel { Spacing = 2, Children = { when, metadata } },
            ContextFlyout = actions,
        };

        // A screen reader reads the row's own content rather than a name invented
        // for it, and its actions are the context menu's — which is what
        // docs/interaction-design.md asks of Narrator here.
        AutomationProperties.SetName(row, record.RowLabel());
        AutomationProperties.SetAutomationId(row, $"record-{record.RecordId}");

        // The row a successful import just added carries a brief highlight. It is
        // colour and is unchanged under Reduce Motion, which is the accepted
        // treatment: what that setting removes is the scroll's animation, not the
        // highlight.
        if (history.Highlighted == record.RecordId
            && SystemBrush("AccentFillColorSelectedTextBackgroundBrush") is { } light)
        {
            row.Background = light;
        }

        return row;
    }

    /// <summary>
    /// Bring a row into view. The sections scroll with the page rather than
    /// inside themselves, so it is the page's scroller that moves and the row's
    /// own offset within it that says where to.
    /// </summary>
    private void ScrollToRow(ulong recordId)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            foreach (ListView list in new[] { PinnedRecords, OtherRecords })
            {
                foreach (object item in list.Items)
                {
                    if (item is not ListViewItem row || row.Tag is not ulong id || id != recordId)
                    {
                        continue;
                    }

                    if (row.XamlRoot is null)
                    {
                        return;
                    }

                    // **A scroll is travel, and travel is what Reduce Motion
                    // removes**: the row still arrives, immediately. The light on
                    // it is colour, which the same rule leaves alone — so only
                    // this half of the accepted answer consults the setting. The
                    // system's own switch is what says so, read at the moment of
                    // use like every other preference here, because it can be
                    // turned on while the window is open.
                    HistoryScroller.ChangeView(
                        null,
                        row.TransformToVisual(HistoryScroller.Content as UIElement)
                            .TransformPoint(new Point(0, 0)).Y,
                        null,
                        disableAnimation: !_system.AnimationsEnabled);
                    return;
                }
            }
        });
    }

    /// <summary>
    /// The viewer: the board at the shown ply, the record beside it, and the
    /// transport under it.
    /// </summary>
    private void ShowViewer(ReplayViewer viewer)
    {
        _replayBoard.Scene = viewer.Scene;

        ReplayProgress.Text = viewer.Progress;
        ReplayMetadata.Text = viewer.MetadataLine;

        Name(ReplayFirst, "replay.first");
        Name(ReplayPrevious, "replay.previous");
        Name(ReplayNext, "replay.next");
        Name(ReplayLast, "replay.last");
        ReplayFirst.IsEnabled = !viewer.IsAtStart;
        ReplayPrevious.IsEnabled = !viewer.IsAtStart;
        ReplayNext.IsEnabled = !viewer.IsAtEnd;
        ReplayLast.IsEnabled = !viewer.IsAtEnd;

        ReplayFlip.Content = Strings.Get("control.flipBoard");

        ShowReplayRecord(viewer);
    }

    /// <summary>
    /// The four transport controls are icon-only, so each carries its word as
    /// both the screen reader's name and the pointer's tooltip.
    /// </summary>
    private static void Name(Button button, string key)
    {
        string word = Strings.Get(key);
        AutomationProperties.SetName(button, word);
        ToolTipService.SetToolTip(button, word);
    }

    /// <summary>
    /// The move record, with the currently displayed move highlighted and every
    /// move selectable.
    ///
    /// The highlight is a filled shape and a heavier weight, never colour alone,
    /// which is the accepted rule for it.
    /// </summary>
    private void ShowReplayRecord(ReplayViewer viewer)
    {
        ReplayRecordRows.Children.Clear();
        IReadOnlyList<string> moves = viewer.MoveRecord;
        int shown = viewer.Ply - 1;

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
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(number, 0);
            row.Children.Add(number);

            row.Children.Add(ReplayCell(viewer, index, 1, shown));
            if (index + 1 < moves.Count)
            {
                row.Children.Add(ReplayCell(viewer, index + 1, 2, shown));
            }

            ReplayRecordRows.Children.Add(row);
        }
    }

    private Button ReplayCell(ReplayViewer viewer, int index, int column, int shown)
    {
        bool current = index == shown;
        Button cell = new()
        {
            Content = new TextBlock
            {
                Text = viewer.MoveRecord[index],
                FontFamily = new FontFamily("Consolas"),
                FontWeight = current ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
            },
            Padding = new Thickness(6, 2, 6, 2),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
        };

        // The highlight on the shown move is a filled shape **and** a heavier
        // weight, never colour alone — the weight above is set whichever way the
        // fill goes, so the accepted rule holds even if the fill does not arrive.
        if (current && SystemBrush("SubtleFillColorSecondaryBrush") is { } fill)
        {
            cell.Background = fill;
        }

        int target = index + 1;
        cell.Click += (_, _) => _history?.Step(replay => replay.Show(target));
        AutomationProperties.SetAutomationId(cell, $"move-{index}");
        Grid.SetColumn(cell, column);
        return cell;
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

    /// <summary>
    /// The Settings destination: three groups, and every control showing what is
    /// **stored** rather than what was last asked for.
    ///
    /// The two pickers' options are the pre-start page's own words — 我先手,
    /// AI 先手, 随机 and the three levels — because they are the same choices,
    /// keyed once in docs/copy.md under `setup.`, and a second set of rows for
    /// the same three options would be two things to keep in step. The two row
    /// labels are the Settings rows' own: 默认先后手 says what this one is that
    /// 先后手 does not.
    ///
    /// Each control's accessibility name is its row label, because the label is a
    /// separate element on the row and a screen reader arriving at the switch
    /// would otherwise have nothing but its state to read. That is the basic
    /// Narrator labelling issue #80 settles this platform at — parity with the
    /// Mac's actual VoiceOver level — and no more.
    /// </summary>
    private void ShowSettings(SettingsScreen settings)
    {
        DefaultsHeader.Text = Strings.Get("settings.defaults.group");
        DefaultsFooter.Text = Strings.Get("settings.defaults.footer");

        DefaultFirstMoverLabel.Text = Strings.Get("settings.defaults.firstMover");
        AutomationProperties.SetName(
            DefaultFirstMover, Strings.Get("settings.defaults.firstMover"));
        DefaultFirstMoverHuman.Content = Strings.Get("setup.iMoveFirst");
        DefaultFirstMoverAi.Content = Strings.Get("setup.aiMovesFirst");
        DefaultFirstMoverRandom.Content = Strings.Get("setup.random");
        DefaultFirstMover.SelectedIndex = settings.DefaultFirstMover switch
        {
            FirstMoverChoice.AiFirst => 1,
            FirstMoverChoice.Random => 2,
            _ => 0,
        };

        DefaultAiLevelLabel.Text = Strings.Get("settings.defaults.aiLevel");
        AutomationProperties.SetName(DefaultAiLevel, Strings.Get("settings.defaults.aiLevel"));
        DefaultLevelFast.Content = Strings.Get("setup.level.fast");
        DefaultLevelStandard.Content = Strings.Get("setup.level.standard");
        DefaultLevelDeep.Content = Strings.Get("setup.level.deep");
        DefaultAiLevel.SelectedIndex = settings.DefaultAiLevel switch
        {
            AiLevel.Fast => 0,
            AiLevel.Deep => 2,
            _ => 1,
        };

        SoundLabel.Text = Strings.Get("settings.sound.label");
        AutomationProperties.SetName(Sound, Strings.Get("settings.sound.label"));
        Sound.IsOn = settings.Sound;

        ConfirmDeleteLabel.Text = Strings.Get("settings.confirmDelete.label");
        AutomationProperties.SetName(
            ConfirmDelete, Strings.Get("settings.confirmDelete.label"));
        ConfirmDelete.IsOn = settings.ConfirmsDeletion;
        ConfirmDeleteFooter.Text = Strings.Get("settings.confirmDelete.footer");
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

        // **The concluding action is a tint moment, once the notice is closed.**
        // The tint rule lists it by name — "the concluding action the
        // play-control cluster carries once a finished game's notice is closed"
        // — and the closing is the whole condition: while the notice stands, its
        // own default action is the tinted one, and at most one tinted element is
        // ever visible. So the accent lands on 开始新对局 exactly when the game is
        // finished and nothing is standing in front of the board, and comes off
        // again the moment the slot goes back to carrying 判和.
        Middle.Style = play.IsOver && play.Notice == ResultNotice.None
            ? (Style)Application.Current.Resources["AccentButtonStyle"]
            : null;

        // 认输 belongs to human-versus-AI and to a game still being played: Free
        // Play has no opponent to resign to, and a finished game has nothing
        // left to end.
        Trailing.Content = Strings.Get("control.resign");
        Trailing.IsEnabled = play.CanResign;
        Trailing.Visibility = Shown(play.IsHumanVersusAi && !play.IsOver);

        // 翻转棋盘, in both modes and for as long as the board is on screen
        // (owner recommendation, 2026-07-31; docs/interaction-design.md § Play
        // controls). It is presentation, so nothing about the game's state
        // enables or disables it, and it takes no tint — the cluster's one
        // tinted moment is the concluding action above.
        Flip.Content = Strings.Get("control.flipBoard");
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
        // the notice offers 回放, which opens the newly created History record
        // from its initial position, and 完成, which returns to the Play home.
        // 回放 had nowhere to go until this destination existed, which is why the
        // recorded notice carried 完成 alone.
        NoticePrimary.Content = Strings.Get(recorded ? "control.done" : "control.save");
        NoticeSecondary.Content = Strings.Get(recorded ? "control.replay" : "control.saveAndNewGame");
        NoticeSecondary.Visibility = Shown(!recorded || play.FiledRecordId is not null);

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

    private void ShowDialog(PlayFlow flow, HistoryFlow history)
    {
        if (_dialogUp)
        {
            return;
        }

        // The destination on screen is the one whose alerts are presented. An
        // import answered while the player has walked to the board would
        // otherwise arrive over a board it says nothing about; it waits, and the
        // History destination presents it when they come back to it — which is
        // the same rule the board's own alerts already follow.
        if (_destination == Destination.History)
        {
            if (history.Alert != HistoryAlert.None)
            {
                ShowHistoryAlert(history, history.Alert);
            }

            return;
        }

        // Settings raises no alert of its own — a preference the file system
        // refused is a control that visibly did not move, which is the truth and
        // has no accepted copy behind it — and it presents nobody else's either,
        // by the same rule the two destinations above follow.
        if (_destination == Destination.Settings)
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

    /// <summary>
    /// The History destination's alerts: the deletion gate and its refusal, and
    /// every answer an import can give that is not the row appearing.
    ///
    /// Each import message says 历史没有改变 explicitly, because no persistent
    /// change is the guarantee the core makes and a reader has no other way to
    /// know it held. Two of the seven carry a second action; the rest are
    /// informational and take 好 alone.
    /// </summary>
    private async void ShowHistoryAlert(HistoryFlow history, HistoryAlert alert)
    {
        _dialogUp = true;

        ContentDialog dialog = new()
        {
            XamlRoot = Root.XamlRoot,
            DefaultButton = ContentDialogButton.Primary,
        };

        switch (alert)
        {
            case HistoryAlert.ConfirmDelete:
                dialog.Title = Strings.Get("alert.deleteGame.title");
                dialog.Content = Strings.Get("alert.deleteGame.message");
                dialog.PrimaryButtonText = Strings.Get("control.delete");
                dialog.CloseButtonText = Strings.Get("control.cancel");

                // A destructive act does not get the emphasis a wanted one gets,
                // and the default is the way out rather than the way through.
                dialog.DefaultButton = ContentDialogButton.Close;
                break;

            case HistoryAlert.DeleteFailed:
                dialog.Title = Strings.Get("alert.deleteFailed.title");
                dialog.Content = Strings.Get("alert.deleteFailed.message");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;

            case HistoryAlert.ImportDuplicate:
                dialog.Title = Strings.Get("alert.importDuplicate.title");
                dialog.Content = Strings.Get("alert.importDuplicate.message");
                dialog.PrimaryButtonText = Strings.Get("control.view");
                dialog.CloseButtonText = Strings.Get("control.ok");
                break;

            case HistoryAlert.ImportSaveFailed:
                dialog.Title = Strings.Get("alert.importSaveFailed.title");
                dialog.Content = Strings.Get("alert.importSaveFailed.message");
                dialog.PrimaryButtonText = Strings.Get("control.tryAgain");
                dialog.CloseButtonText = Strings.Get("control.cancel");
                break;

            default:
                (string title, string message) = alert switch
                {
                    HistoryAlert.ImportConflict =>
                        ("alert.importConflict.title", "alert.importConflict.message"),
                    HistoryAlert.ImportNewerVersion =>
                        ("alert.importNewerVersion.title", "alert.importNewerVersion.message"),
                    HistoryAlert.ImportDamagedRecord =>
                        ("alert.importDamagedRecord.title", "alert.importDamagedRecord.message"),
                    _ => ("alert.importUnreadable.title", "alert.importUnreadable.message"),
                };

                // Informational plus nothing to navigate to: 好 alone. The
                // conflict and the damaged record both name deleting the existing
                // record as the route forward rather than offering it as a
                // button, because that deletion is permanent and should be
                // reached deliberately.
                dialog.Title = Strings.Get(title);
                dialog.Content = Strings.Get(message);
                dialog.CloseButtonText = Strings.Get("control.ok");
                dialog.DefaultButton = ContentDialogButton.Close;
                break;
        }

        ContentDialogResult result = await dialog.ShowAsync();
        _dialogUp = false;
        if (history.Alert != alert)
        {
            // The situation moved on while the reader was reading. This answer is
            // about a question that is no longer being asked — but whatever
            // replaced it published while a dialog was up, so nothing presented
            // it, and without this the destination would sit behind an alert that
            // is set and invisible with its rows refusing to answer. Redrawing is
            // what puts the new one on screen.
            Refresh();
            return;
        }

        bool confirmed = result == ContentDialogResult.Primary;
        switch (alert)
        {
            case HistoryAlert.ConfirmDelete when confirmed:
            case HistoryAlert.DeleteFailed when confirmed:
                history.ConfirmDelete();
                break;
            case HistoryAlert.ImportDuplicate when confirmed:
                history.ViewDuplicate();
                break;
            case HistoryAlert.ImportSaveFailed when confirmed:
                history.RetryImport();
                break;
            default:
                history.DismissAlert();
                break;
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
            // The situation moved on while the player was reading; this answer is
            // about a question that is no longer being asked. **Whatever replaced
            // it will not present itself**, which this comment used to assume it
            // would: it published while a dialog was up, and ShowDialog runs only
            // from Refresh. Redrawing here is what puts it on screen. (The same
            // shape was in the History destination's handler and is fixed there
            // too.)
            Refresh();
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
            // As above: what replaced this published behind a dialog, so nothing
            // presented it. Redrawing does.
            Refresh();
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

    /// <summary>
    /// A system brush by name, or nothing.
    ///
    /// A `{ThemeResource}` in XAML fails at parse time and is caught by building;
    /// an indexer into <c>Application.Current.Resources</c> fails at the moment
    /// it runs, with a <c>KeyNotFoundException</c> out of whatever was drawing.
    /// Every brush this file asks for by name is decoration whose absence costs a
    /// row its tint and nothing else — and this frontend's XAML is the one part
    /// of it no machine here can run, so the difference between a plain row and a
    /// window that will not open is worth four lines. The play screen's verify
    /// found a reachable crash in exactly this class of code.
    /// </summary>
    private static Brush? SystemBrush(string key) =>
        Application.Current.Resources.TryGetValue(key, out object? found) ? found as Brush : null;

    private void ShowFailure(string titleKey, MxqException failure) =>
        ShowFailure(titleKey, HistoryFlow.Diagnose(failure));

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
        HistoryPage.Visibility = Visibility.Collapsed;
        ViewerPage.Visibility = Visibility.Collapsed;
        Back.Visibility = Visibility.Collapsed;
    }

    /// <summary>
    /// The failure this window cannot come back from: the core did not start, or
    /// the first game did not.
    ///
    /// A History read that failed is not one of them — 历史未能载入 is one
    /// destination's screen and leaving the destination puts it away — so the two
    /// are told apart rather than both being "the failure screen is up".
    /// </summary>
    private void ShowFatalFailure(string titleKey, MxqException failure)
    {
        _fatal = true;
        ShowFailure(titleKey, failure);
    }

    /// <summary>
    /// The application's backstop, arriving here. Everything this repository
    /// knows how to be refused is answered where it happens; what reaches this
    /// is something nobody anticipated, so it stops the screen offering play and
    /// says what it was. The game itself is whole — the store commits every move
    /// inside its own call — and 对局未能开始 is the honest title for a screen
    /// that can no longer be played on.
    /// </summary>
    internal void ReportUnexpected(Exception failure)
    {
        _fatal = true;
        ShowFailure("failure.gameDidNotStart", $"{failure.GetType().Name}\n{failure.Message}");
    }

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
