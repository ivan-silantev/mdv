Name:           mdv
Version:        0.1.0
Release:        1%{?dist}
Summary:        Markdown renderer CLI in the terminal

License:        MIT
URL:            https://github.com/ivan-silantev/mdv
Source0:        https://github.com/ivan-silantev/mdv/archive/refs/tags/v%{version}.tar.gz

BuildRequires:  zig

%description
Markdown renderer CLI in the terminal.
A fast and beautiful markdown renderer for your terminal.

%prep
%setup -q -n md-%{version}

%build
# Build using zig
zig build -Doptimize=ReleaseSafe

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/bin
install -m 0755 zig-out/bin/mdv %{buildroot}/usr/bin/mdv

%files
/usr/bin/mdv
