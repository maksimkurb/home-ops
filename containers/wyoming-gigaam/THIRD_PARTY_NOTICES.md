# Third-party notices

This image redistributes model artifacts used at runtime.

## GigaAM

- Source: https://github.com/salute-developers/GigaAM
- License: MIT
- The upstream license text is included at `/usr/share/licenses/GigaAM/LICENSE`.

## pyannote/segmentation-3.0

- Source: https://huggingface.co/pyannote/segmentation-3.0
- License declared by the model repository: MIT
- The original Hugging Face snapshot, including its model card and repository metadata, is preserved under the baked Hugging Face cache in `/opt/models/huggingface`.

The Hugging Face access token is used only as a BuildKit build secret and is not stored in the final image.
