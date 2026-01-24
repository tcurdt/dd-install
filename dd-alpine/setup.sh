# nix

echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

nix-channel --add https://nixos.org/channels/nixos-25.11 nixpkgs
nix-channel --update

# containers

rc-service cgroups start
rc-update add cgroups boot

cat > /etc/containers/registries.conf << 'EOF'
unqualified-search-registries = ["docker.io", "quay.io", "ghcr.io"]

[[registry]]
location = "docker.io"

[[registry]]
location = "quay.io"

[[registry]]
location = "ghcr.io"
EOF

cat > /etc/containers/policy.json << 'EOF'
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ]
}
EOF
