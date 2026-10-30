{
  description = "Original Xbox Linux port research environment";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";
  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        git cmake ninja pkg-config clang gdb binutils
        (python3.withPackages (p: [ p.capstone p.pytest ]))
        SDL2 libepoxy libGL openssl ffmpeg
      ];
    };
  };
}
