//! Reference values for the Swift port of the fsrs-rs optimizer (see ADR 0002).
//!
//! Reads review histories as written by `SyntheticLearner` in the VocabCore tests and
//! prints what fsrs-rs computes for them:
//!
//!     cargo run --release -- ../../Packages/VocabCore/Tests/VocabCoreTests/Resources/fsrs-reference-histories.json \
//!         > ../../Packages/VocabCore/Tests/VocabCoreTests/Resources/fsrs-reference-results.json

use fsrs::{
    ComputeParametersInput, DEFAULT_PARAMETERS, FSRS, FSRSItem, FSRSReview, ModelEvaluation,
    TrainingConfig, compute_parameters,
};
use serde::{Deserialize, Serialize};

/// Same as the default number of steps in the app's learning options.
const RELEARNING_STEPS: usize = 2;

#[derive(Deserialize)]
struct History {
    day: u32,
    reviews: Vec<[u32; 2]>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Evaluation {
    log_loss: f32,
    rmse: f32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Results {
    item_count: usize,
    default_evaluation: Evaluation,
    /// Default training configuration: batches of 512.
    parameters: Vec<f32>,
    evaluation: Evaluation,
    /// All items in one batch, so the shuffled batch order does not matter.
    single_batch_parameters: Vec<f32>,
}

/// One item per review on a later day than the previous one, ordered by day and then
/// by card, as `TrainingItem.items(from:calendar:)` orders them.
fn items(histories: &[History]) -> Vec<FSRSItem> {
    let mut keyed = Vec::new();
    for (card, history) in histories.iter().enumerate() {
        let mut day = history.day;
        let reviews: Vec<FSRSReview> = history
            .reviews
            .iter()
            .map(|&[rating, delta_t]| FSRSReview { rating, delta_t })
            .collect();
        for (i, review) in reviews.iter().enumerate() {
            day += review.delta_t;
            if review.delta_t > 0 {
                keyed.push(((day, card), FSRSItem { reviews: reviews[..=i].to_vec() }));
            }
        }
    }
    keyed.sort_by_key(|(key, _)| *key);
    keyed.into_iter().map(|(_, item)| item).collect()
}

fn evaluate(parameters: &[f32], items: &[FSRSItem]) -> Evaluation {
    let ModelEvaluation { log_loss, rmse_bins } = FSRS::new(parameters)
        .unwrap()
        .evaluate(items.to_vec(), |_| true)
        .unwrap();
    Evaluation { log_loss, rmse: rmse_bins }
}

fn train(items: &[FSRSItem], training_config: TrainingConfig) -> Vec<f32> {
    compute_parameters(ComputeParametersInput {
        train_set: items.to_vec(),
        num_relearning_steps: Some(RELEARNING_STEPS),
        training_config: Some(training_config),
        ..Default::default()
    })
    .unwrap()
}

fn main() {
    let path = std::env::args().nth(1).expect("path to the histories");
    let histories: Vec<History> = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    let items = items(&histories);

    let parameters = train(&items, TrainingConfig::default());
    let single_batch_parameters = train(
        &items,
        TrainingConfig { batch_size: items.len() + 1, ..TrainingConfig::default() },
    );
    let results = Results {
        item_count: items.len(),
        default_evaluation: evaluate(&DEFAULT_PARAMETERS, &items),
        evaluation: evaluate(&parameters, &items),
        parameters,
        single_batch_parameters,
    };
    println!("{}", serde_json::to_string_pretty(&results).unwrap());
}
