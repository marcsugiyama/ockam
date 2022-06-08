use std::time::Duration;

use crate::config::OckamConfig;
use crate::util::{self, connect_to};
use clap::Args;
use cli_table::{format::Justify, print_stdout, Cell, Style, Table};
use crossbeam_channel::{bounded, Sender};
use ockam::{
    protocols::nodeman::{req::NodeManMessage, resp::NodeManReply},
    Context, Route,
};

#[derive(Clone, Debug, Args)]
pub struct ListCommand {}

impl ListCommand {
    pub fn run(cfg: &mut OckamConfig, _: ListCommand) {
        let nodes = cfg.get_nodes();

        if nodes.is_empty() {
            println!("No nodes registered on this system!");
            std::process::exit(0);
        }

        // Before printing node state we have to verify it.  This
        // happens by sending a QueryStatus request to every node on
        // record.  If the function fails, then it is assumed not to
        // be up.  Also, if the function returns, but yields a
        // different pid, then we update the pid stored in the config.
        let node_names = nodes.iter().map(|(name, _)| name.clone()).collect();
        verify_pids(cfg, node_names);

        let table = cfg
            .get_nodes()
            .iter()
            .fold(vec![], |mut acc, (name, node_cfg)| {
                let row = vec![
                    name.cell(),
                    node_cfg.port.cell().justify(Justify::Right),
                    match node_cfg.pid {
                        Some(pid) => format!("Yes (pid: {})", pid),
                        None => "No".into(),
                    }
                    .cell()
                    .justify(Justify::Left),
                    cfg.log_path(name).cell(),
                ];
                acc.push(row);
                acc
            })
            .table()
            .title(vec![
                "Node name".cell().bold(true),
                "API port".cell().bold(true),
                "Running".cell().bold(true),
                "Log path".cell().bold(true),
            ]);

        if let Err(e) = print_stdout(table) {
            eprintln!("failed to print node status: {}", e);
        }
    }
}

fn verify_pids(cfg: &mut OckamConfig, nodes: Vec<String>) {
    for node_name in nodes {
        let node_cfg = cfg.get_nodes().get(&node_name).unwrap();

        let (tx, rx) = bounded(1);
        println!("Checking state for node '{}'", node_name);
        connect_to(node_cfg.port, tx, query_pid);
        let verified_pid = rx.recv().unwrap();

        if node_cfg.pid != verified_pid {
            if let Err(e) = cfg.update_pid(&node_name, verified_pid) {
                eprintln!("failed to update pid for node {}: {}", node_name, e);
            }
        }
    }
}

pub async fn query_pid(
    mut ctx: Context,
    tx: Sender<Option<i32>>,
    mut base_route: Route,
) -> anyhow::Result<()> {
    ctx.send(
        base_route.modify().append("_internal.nodeman"),
        NodeManMessage::Status,
    )
    .await?;

    let reply = match ctx
        .receive_duration_timeout::<NodeManReply>(Duration::from_millis(200))
        .await
    {
        Ok(r) => r.take().body(),
        Err(_) => {
            tx.send(None).unwrap();
            return util::stop_node(ctx).await;
        }
    };

    let pid = match reply {
        NodeManReply::Status { pid, .. } => pid,
    };

    tx.send(Some(pid)).unwrap();
    util::stop_node(ctx).await
}