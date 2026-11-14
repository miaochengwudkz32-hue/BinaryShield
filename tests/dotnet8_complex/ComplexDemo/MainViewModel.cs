using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace ComplexDemo
{
    // MVVM view model. All members the XAML binds to are public, so KeepPublicApi keeps their names.
    public class MainViewModel : INotifyPropertyChanged
    {
        private static readonly string[] Regions = { "North", "South", "East", "West" };

        private readonly List<CustomerModel> _all = new List<CustomerModel>();
        private CustomerModel _selectedCustomer;
        private int _selectedTabIndex;
        private int _clickCount;
        private string _filterRegion = "All";
        private string _status;

        public MainViewModel()
        {
            for (int i = 0; i < 500; i++)
            {
                _all.Add(new CustomerModel
                {
                    Id = i + 1,
                    Name = "Customer " + (i + 1).ToString("000"),
                    Region = Regions[i % 4],
                    Balance = (i * 37 % 1000) * 12.5m
                });
            }

            IncrementCommand = new RelayCommand(_ => Increment());
            FilterCommand = new RelayCommand(p => ApplyFilter(p as string ?? "All"));
            ShowDetailsCommand = new RelayCommand(_ => DetailsRequested?.Invoke());
            ApplyFilter("All");
        }

        public ObservableCollection<CustomerModel> FilteredCustomers { get; } = new ObservableCollection<CustomerModel>();

        public CustomerModel SelectedCustomer
        {
            get => _selectedCustomer;
            set
            {
                if (Set(ref _selectedCustomer, value) && value != null)
                {
                    TestLog.Write("selected=" + value.Name);
                }
            }
        }

        public int SelectedTabIndex
        {
            get => _selectedTabIndex;
            set
            {
                if (Set(ref _selectedTabIndex, value))
                {
                    TestLog.Write("vm SelectedTabIndex=" + value);
                }
            }
        }

        public int ClickCount
        {
            get => _clickCount;
            private set => Set(ref _clickCount, value);
        }

        public string FilterRegion
        {
            get => _filterRegion;
            private set => Set(ref _filterRegion, value);
        }

        public string Status
        {
            get => _status;
            private set => Set(ref _status, value);
        }

        public RelayCommand IncrementCommand { get; }

        public RelayCommand FilterCommand { get; }

        public RelayCommand ShowDetailsCommand { get; }

        // Raised when the user asks for the details dialog. The window opens it.
        public event Action DetailsRequested;

        // Raised after the filter has been applied to FilteredCustomers.
        public event Action FilterChanged;

        public event PropertyChangedEventHandler PropertyChanged;

        private void Increment()
        {
            ClickCount++;
            TestLog.Write("counter click #" + ClickCount);
        }

        private void ApplyFilter(string region)
        {
            FilteredCustomers.Clear();
            foreach (var customer in _all)
            {
                if (region == "All" || customer.Region == region)
                {
                    FilteredCustomers.Add(customer);
                }
            }
            FilterRegion = region;
            Status = "Showing " + FilteredCustomers.Count + " of " + _all.Count + " customers";
            FilterChanged?.Invoke();
        }

        private bool Set<T>(ref T field, T value, [CallerMemberName] string name = null)
        {
            if (EqualityComparer<T>.Default.Equals(field, value))
            {
                return false;
            }
            field = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
            return true;
        }
    }
}
