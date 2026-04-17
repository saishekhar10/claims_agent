import os

SUPPORTED_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg", ".txt"}

def load_claim_folder(folder_path: str) -> dict:
    """
    Walk a folder and return dict:
      { "relative/path.ext": {"path": "/abs/path", "ext": ".pdf", "filename": "name.pdf"} }
    Skips hidden files (dotfiles).
    """
    result = {}
    for root, dirs, files in os.walk(folder_path):
        # Skip hidden directories in-place
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in files:
            if fname.startswith('.'):
                continue
            fpath = os.path.join(root, fname)
            ext = os.path.splitext(fname)[1].lower()
            rel = os.path.relpath(fpath, folder_path)
            result[rel] = {
                "path": fpath,
                "ext": ext,
                "filename": fname,
                "supported": ext in SUPPORTED_EXTENSIONS,
            }
    return result


def read_text_file(file_path: str) -> str:
    """
    Read and return the contents of a text file.
    
    Args:
        file_path: Path to the text file to read
        
    Returns:
        String containing the file contents
        
    Raises:
        FileNotFoundError: If the file doesn't exist
        UnicodeDecodeError: If the file isn't valid UTF-8 text
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        return f.read()