using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace ComplexDemo
{
    public partial class DetailsWindow : Window
    {
        public DetailsWindow()
        {
            InitializeComponent();
            Opened += (s, e) => Dispatcher.UIThread.Post(() =>
            {
                TestLog.Write("details view name=" + TxtDetailName.Text);
                TestLog.LogLayout("details", this);
            }, DispatcherPriority.Background);
        }

        private void OnCloseClick(object sender, RoutedEventArgs e)
        {
            TestLog.Write("details closed");
            Close();
        }
    }
}
