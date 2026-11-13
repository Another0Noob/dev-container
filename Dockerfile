# syntax=docker/dockerfile:1
#
# App layer: the bits that change day to day (Python CLI tools, fish defaults,
# Neovim config). It starts from the image built by ./Dockerfile.base, so a
# rebuild here is seconds instead of minutes.
#
#   ./run-container . --build          builds the base first if it is missing
#   podman build -f Dockerfile -t cachyos-dev:latest .
#
ARG BASE_IMAGE=cachyos-dev-base:local
FROM ${BASE_IMAGE}

# Redclared: build args do not cross a FROM, and these are needed for the
# cache-mount ownership and the COPY --chown below. USER, ENV and PATH already
# come from the base image.
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# ---- Python CLI tools ------------------------------------------------------
# mistral-vibe and termux-language-server were previously installed via yay, but
# that pulls ~40 python-* packages, several of which are not in the Arch repos
# and get compiled from source by makepkg (Rust / C builds -- very slow, and the
# makedepends stay installed afterwards). Both are published as prebuilt wheels
# on PyPI, so uv takes seconds and keeps the image lean; the uv cache mount means
# even a full rebuild of this layer reuses already-downloaded wheels.
# Tools land in ~/.local/share/uv with launchers in ~/.local/bin -- neither is a
# runtime volume, so they stay visible.
RUN --mount=type=cache,target=/home/${USERNAME}/.cache/uv,uid=${USER_UID},gid=${USER_GID},sharing=locked \
  uv tool install mistral-vibe \
  && uv tool install termux-language-server \
  && uv tool list

# ---- Cache dirs, fish defaults ---------------------------------------------
# Cache dirs are created here so named volumes inherit the user's ownership.
# The two gitconfig files are bind-mount targets (see compose.yaml); creating
# them keeps the engine from turning a missing target into a directory.
# PATH and EDITOR come from the base image's ENV, so fish needs no extra setup
# for them.
RUN mkdir -p ~/.cargo/registry ~/.cargo/git ~/go/pkg ~/.npm-global ~/.cache \
  ~/.local/share/nvim ~/.local/state/nvim ~/.config/fish/conf.d \
  ~/.pi/agent ~/.vibe \
  && touch ~/.gitconfig ~/.gitconfig.host \
  && printf '%s\n' \
  'abbr -a vim nvim' \
  'abbr -a lg lazygit' \
  > ~/.config/fish/conf.d/dev.fish

# ---- Neovim config: copied into the image at build time (no host mount) ----
# Put a copy of your config in ./nvim-config next to this Dockerfile first.
COPY --chown=${USERNAME}:${USER_GID} nvim-config/ /home/${USERNAME}/.config/nvim/

# LazyVim is deliberately NOT prewarmed here. ~/.local/share/nvim is a named
# volume at runtime (compose.yaml), and an empty volume is seeded from the image
# only once: a rebuild never reaches an existing volume, while every rebuild
# pays for ~55 git clones plus the tree-sitter parser builds. The first container
# start populates the persistent volume instead, which is paid once, ever.
#
# If you want it baked anyway (fresh volumes / CI images), this reuses a cache
# mount instead of re-cloning on every rebuild:
#
# RUN --mount=type=cache,target=/home/${USERNAME}/.cache/nvim-prewarm,uid=${USER_UID},gid=${USER_GID},sharing=locked \
#   XDG_DATA_HOME=/home/${USERNAME}/.cache/nvim-prewarm nvim --headless "+Lazy! sync" +qa \
#   && mkdir -p ~/.local/share/nvim \
#   && cp -a /home/${USERNAME}/.cache/nvim-prewarm/nvim/. ~/.local/share/nvim/

WORKDIR /workspace
CMD ["fish"]
