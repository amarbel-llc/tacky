use std::io::Read;

use clap::{Parser, Subcommand};
use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2_app_kit::{NSPasteboard, NSPasteboardItem};
use objc2_foundation::{NSArray, NSData, NSString};

#[derive(Parser)]
#[command(name = "tacky")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Copy data to the pasteboard
    Copy {
        /// UTI type and file pairs (use - for stdin)
        #[arg(short = 'i', long = "item", num_args = 2, action = clap::ArgAction::Append, value_names = ["UTI", "FILE"])]
        item: Vec<String>,
    },
    /// Paste data from the pasteboard
    Paste {
        /// UTI type to paste
        #[arg(short, long)]
        uti: Option<String>,
        /// List available UTI types
        #[arg(short, long)]
        list: bool,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Copy { item }) => {
            let entries: Vec<(&str, &str)> = item
                .chunks(2)
                .map(|c| (c[0].as_str(), c[1].as_str()))
                .collect();
            copy(&entries);
        }
        Some(Commands::Paste { list: true, .. }) => {
            list_uti();
        }
        Some(Commands::Paste { uti: Some(uti), .. }) => {
            paste(&uti);
        }
        Some(Commands::Paste {
            uti: None,
            list: false,
        }) => {
            eprintln!("error: specify --uti or --list");
            std::process::exit(1);
        }
        None => {
            Cli::parse_from(["tacky", "--help"]);
        }
    }
}

fn copy(entries: &[(&str, &str)]) {
    unsafe {
        let pb = NSPasteboard::generalPasteboard();

        let types: Vec<Retained<NSString>> =
            entries.iter().map(|(uti, _)| NSString::from_str(uti)).collect();
        let type_refs: Vec<&NSString> = types.iter().map(|s| s.as_ref()).collect();
        let ns_types = NSArray::from_slice(&type_refs);
        pb.declareTypes_owner(&ns_types, None::<&AnyObject>);

        let mut stdin_data: Option<Vec<u8>> = None;

        for (uti, path) in entries {
            let data = if *path == "-" {
                if stdin_data.is_none() {
                    let mut buf = Vec::new();
                    std::io::stdin()
                        .read_to_end(&mut buf)
                        .expect("failed to read stdin");
                    stdin_data = Some(buf);
                }
                stdin_data.as_ref().unwrap().clone()
            } else {
                std::fs::read(path).unwrap_or_else(|e| {
                    eprintln!("error reading {path}: {e}");
                    std::process::exit(1);
                })
            };

            let ns_data = NSData::with_bytes(&data);
            let ns_type = NSString::from_str(uti);
            pb.setData_forType(Some(&*ns_data), &ns_type);
        }
    }
}

fn paste(uti: &str) {
    let pb = NSPasteboard::generalPasteboard();
    let ns_uti = NSString::from_str(uti);

    if let Some(items) = pb.pasteboardItems() {
        for i in 0..items.count() {
            let item: &NSPasteboardItem = &items.objectAtIndex(i);
            if let Some(value) = item.stringForType(&ns_uti) {
                println!("{value}");
                return;
            }
        }
    }
}

fn list_uti() {
    let pb = NSPasteboard::generalPasteboard();

    if let Some(items) = pb.pasteboardItems() {
        for i in 0..items.count() {
            let item: &NSPasteboardItem = &items.objectAtIndex(i);
            let types = item.types();
            for j in 0..types.count() {
                let t: &NSString = &types.objectAtIndex(j);
                println!("{t}");
            }
        }
    }
}
