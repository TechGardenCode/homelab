# Argo CD AOE (App of Everything)

This project provides a way to self-host Argo CD using Helm and the "App of Everything" pattern. It installs Argo CD onto your Kubernetes cluster and configures it so that Argo CD self-manages itself for future updates and configuration changes.

## Features

- **Self-Managed Argo CD**: Argo CD is configured to manage its own updates and configuration changes.
- **Declarative Projects and Applications**: Provides folders to declaratively add Argo CD projects and applications, allowing users to bootstrap their clusters with pre-defined applications.

## Installation

1. Clone the repository:
    ```sh
    git clone https://github.com/techgardencode/argo-cd-aoe.git
    cd argo-cd-aoe
    ```

2. Install Argo CD using Helm:
    ```sh
    sh ./install/install-argocd.sh
    ```

## Usage

- Add your Argo CD projects to the `projects` folder.
- Add your Argo CD applications to the `apps` folder.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the MIT License.