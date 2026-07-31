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
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
