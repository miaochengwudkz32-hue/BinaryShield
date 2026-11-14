using System;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;

namespace ListDemo
{
    public partial class MainWindow : Window
    {
        // Test log written next to the exe, so the UI test can check that clicks and scrolls really reached the code.
        private static readonly string LogPath = Path.Combine(AppContext.BaseDirectory, "app_test.log");

        private int _clicks;

        public MainWindow()
        {
            InitializeComponent();
            Opened += (s, e) =>
            {
                int items = (DataContext as MainViewModel)?.Items.Count ?? -1;
                Log("window opened; items=" + items);
            };
            ItemList.AddHandler(InputElement.PointerWheelChangedEvent, OnListWheel, RoutingStrategies.Tunnel);
        }

        private void OnButtonClick(object sender, RoutedEventArgs e)
        {
            _clicks++;
            if (DataContext is MainViewModel vm)
            {
                vm.ClickCount = _clicks;
            }
            Log("button click #" + _clicks);
        }

        private void OnListWheel(object sender, PointerWheelEventArgs e)
        {
            Log("wheel delta.y=" + e.Delta.Y.ToString("F1"));
            Dispatcher.UIThread.Post(() =>
            {
                var sv = ItemList.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
                if (sv != null)
                {
                    Log("scroll offset.y=" + sv.Offset.Y.ToString("F1"));
                }
            }, DispatcherPriority.Background);
        }

        private static void Log(string message)
        {
            try
            {
                File.AppendAllText(LogPath, DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + Environment.NewLine);
            }
            catch
            {
                // Logging must never break the UI.
            }
        }
    }
}
