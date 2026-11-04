FROM docker.io/cachyos/cachyos-v3:latest

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# ---- System packages -------------------------------------------------------
# pacman's hook/scriptlet sandbox tries to create a network namespace, which is
# not permitted inside an (unprivileged) container build, hence the sed.
RUN sed -i '/^\[options\]/a DisableSandboxNetwork' /etc/pacman.conf \
  && pacman -Syu --noconfirm --needed \
  base-devel git openssh sudo \
  fish neovim kitty-terminfo \
  ripgrep fd fzf lazygit tree-sitter-cli unzip curl wget \
  python luarocks \
  nodejs npm pnpm yarn \
  go gopls delve golangci-lint \
  rustup \
  tmux \
  yay \
  && rm -rf /var/cache/pacman/pkg/*

# ---- Non-root user (UID/GID match the host so bind mounts stay writable) ---
# -l: don't create a huge sparse lastlog/faillog entry for a high UID
RUN groupadd -g ${USER_GID} ${USERNAME} 2>/dev/null || true \
  && useradd -l -m -u ${USER_UID} -g ${USER_GID} -s /usr/bin/fish ${USERNAME} \
  && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
  && chmod 0440 /etc/sudoers.d/${USERNAME} \
  && mkdir -p /workspace \
  && chown ${USERNAME}:${USER_GID} /workspace

USER ${USERNAME}
ENV HOME=/home/${USERNAME} \
  CARGO_HOME=/home/${USERNAME}/.cargo \
  RUSTUP_HOME=/home/${USERNAME}/.rustup \
  GOPATH=/home/${USERNAME}/go \
  NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global \
  SHELL=/usr/bin/fish \
  EDITOR=nvim \
  LANG=C.UTF-8 \
  COLORTERM=truecolor
ENV PATH=${CARGO_HOME}/bin:${GOPATH}/bin:${NPM_CONFIG_PREFIX}/bin:${PATH}
WORKDIR /home/${USERNAME}

# ---- AUR packages (yay must run as the non-root user) -----------------------
RUN yay -S --noconfirm --needed --cleanafter pi umbriel-git \
  && yay -Scc --noconfirm \
  && rm -rf ~/.cache/yay

# ---- Rust toolchain, cache dirs, fish defaults ------------------------------
# Cache dirs are created here so named volumes inherit the user's ownership.
# PATH and EDITOR come from ENV above, so fish needs no extra setup for them.
RUN rustup default stable \
  && rustup component add rust-analyzer clippy rustfmt \
  && mkdir -p ~/.cargo/registry ~/.cargo/git ~/go/pkg ~/.npm-global ~/.cache \
  ~/.local/share/nvim ~/.local/state/nvim ~/.config/fish/conf.d \
  && printf '%s\n' \
  'abbr -a vim nvim' \
  'abbr -a lg lazygit' \
  > ~/.config/fish/conf.d/dev.fish

# ---- Neovim config: copied into the image at build time (no host mount) ----
# Put a copy of your config in ./nvim-config next to this Dockerfile first.
COPY --chown=${USERNAME}:${USER_GID} nvim-config/ /home/${USERNAME}/.config/nvim/
RUN nvim --headless "+Lazy! sync" +qa || true

WORKDIR /workspace
CMD ["fish"]
