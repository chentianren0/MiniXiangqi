using Microsoft.UI.Xaml;

namespace MiniXiangqi.App;

/// <summary>
/// The application. One main window per platform, as the architecture contract
/// requires everywhere.
/// </summary>
public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }

    /// <summary>
    /// The backstop, and deliberately a visible one.
    ///
    /// Everything the play screen does runs under an event handler or under a
    /// dialog's completion, and an exception from either reaches here rather
    /// than any caller — with nothing to catch it the process disappears
    /// mid-game and the player is told nothing at all. Every path this
    /// repository knows about is answered where it happens; this is for the one
    /// nobody thought of.
    ///
    /// It marks the exception handled rather than letting the process go,
    /// because terminating tells the player less and saves nothing: the store
    /// commits every move inside its own call, so the game on disk is whole
    /// either way, and a screen naming the call that refused is a screen
    /// somebody can report. The window it hands the failure to stops offering
    /// play, so a broken state is shown rather than played on.
    /// </summary>
    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs args)
    {
        if (_window is not MainWindow window)
        {
            return;
        }

        args.Handled = true;
        window.ReportUnexpected(args.Exception);
    }
}
