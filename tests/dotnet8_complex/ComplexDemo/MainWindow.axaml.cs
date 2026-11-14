using System;
using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Threading;

namespace ComplexDemo
{
    public partial class MainWindow : Window
    {
        private MainViewModel _vm;

        public MainWindow()
        {
            InitializeComponent();
            Opened += OnOpened;
            MainTabs.SelectionChanged += OnTabChanged;
        }

        private void OnOpened(object sender, EventArgs e)
        {
            _vm = DataContext as MainViewModel;
            if (_vm == null)
            {
                TestLog.Write("error: DataContext is not MainViewModel");
                return;
            }

            TestLog.Write("window opened; customers=" + _vm.FilteredCustomers.Count);
            _vm.DetailsRequested += ShowDetails;
            _vm.FilterChanged += LogFilter;
            _vm.PropertyChanged += OnViewModelChanged;

            Later(() =>
            {
                TestLog.Write("view grid rows=" + GridRowCount());
                TestLog.LogLayout("main", this);
            });
        }

        // Re-log positions after a tab change, because the tab content is laid out again.
        private void OnTabChanged(object sender, SelectionChangedEventArgs e)
        {
            if (e.Source != MainTabs)
            {
                return;
            }
            Later(() => TestLog.LogLayout("main", this));
        }

        private void OnViewModelChanged(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == "ClickCount")
            {
                Later(() => TestLog.Write("view CountText=" + TxtCount.Text));
            }
        }

        private void LogFilter()
        {
            Later(() => TestLog.Write("filter=" + _vm.FilterRegion + " vm=" + _vm.FilteredCustomers.Count + " view=" + GridRowCount().Split(' ')[0]));
        }

        private void ShowDetails()
        {
            var customer = _vm.SelectedCustomer;
            TestLog.Write("details opened name=" + (customer != null ? customer.Name : "none"));
            if (customer == null)
            {
                return;
            }

            var dialog = new DetailsWindow { DataContext = customer };
            _ = dialog.ShowDialog(this);
        }

        // Rows the grid is bound to. Avalonia 11.0.10's DataGrid has no public item count, so this is the
        // count of its ItemsSource collection; the rendered rows are checked by screenshots.
        private string GridRowCount()
        {
            var count = (CustomerGrid.ItemsSource as System.Collections.ICollection)?.Count ?? -1;
            bool bound = ReferenceEquals(CustomerGrid.ItemsSource, _vm.FilteredCustomers);
            return count + " bound=" + bound;
        }

        // Runs after the current layout and render pass, so the logged state is what is on screen.
        private static void Later(Action action) => Dispatcher.UIThread.Post(action, DispatcherPriority.Background);
    }
}
