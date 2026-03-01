#!/usr/bin/env nu

use ~/.fin-plan/config.nu [income_filters, expenses_filters, expense_category_order]

const outdir = "fin-plan-output"

def main [...csv_files: path, --retry] {
  if ($csv_files | length) == 0 {
    print --stderr "error: need to provide paths"
    exit 1
  }

  if (open ...$csv_files | length) == 0 {
    print --stderr "error: no files found"
    exit 1
  }

  mkdir $outdir

  let data = (
    open ...$csv_files
    | select "Account Number" "Post Date" "Description" "Debit" "Credit"
    | rename account post_date description debit credit
    | sort-by account post_date
    | insert category null
    | insert note null
    | try_categorize
  )

  # process income entries
  let income = (
    $data
    | where credit != ""
    | reject debit
    | rename --column {credit: amount}
    | process_accounts "income" $retry
    | each { |entry| verify_all_have_category $entry }
    | group-by --to-table category
    | each { |category|
      $category
      | update items { sort-by note | select amount note }
    }
  )

  # process expenses entries
  let expenses = (
    $data
    | where debit != ""
    | reject credit
    | rename --column {debit: amount}
    | process_accounts "expenses" $retry
    | each { |entry| verify_all_have_category $entry }
    | group-by --to-table category
    | each { |category|
      $category
      | update items { sort-by note | select amount note }
    }
  )

  # output into csv
  let output = { income: $income, expenses: $expenses }

  let result_file = $outdir | path join "results.csv"
}

# attempts to categorize incomes and expenses based on
# the filters provided
def try_categorize [] {
  $in
  | each { |entry|
    if (is_income $entry) {
      $entry
      | conditional_update (income_filters)
    } else if (is_expense $entry) {
      $entry
      | conditional_update (expenses_filters)
    } else {
      error make $"entry is neither income nor expense: ($entry)"
    }
  }
}

def is_income [entry] {
  $entry.credit != ""
}

export def is_expense [entry] {
  $entry.debit != ""
}

# search for an update that matches, then apply that update if there is one
#
# an update is a record:
# 
#   { cond: closure, category: string, note?: string }
# 
#   - `cond`: a predicate that defines whether an update should apply
#   - `category`: the category to apply
#   - `note` (optional): the note to apply
#
# For example,
#
# ```
# {
#   cond: { $in.description == "Fidelity" },
#   category: "Savings",
#   note: "Retirement",
# }
# ```
def conditional_update [updates: table] {

  let entry = $in

  let update = (
    $updates
    | where { |filter| $entry | do $filter.cond }
    | first
  )

  if $update == null {
    return $entry
  }

  $entry
  | update category $update.category
  | update note $update.note?
}

# allow the user to edit entries in LibreOffice, sorted
# by account
def process_accounts [kind: string, retry: bool] {
    $in
    | group-by --to-table account
    | insert out { |account| $outdir | path join $"($kind).($account.account).csv" }
    | each { |account|
      # check if the out file exists
      let file_exists = (ls $account.out | length) > 0

      # create the CSV file for writing if retrying
      # or if the file doesn't exist
      # TODO: get rid of the `-f` flag when done testing
      if not $retry or not $file_exists {
        $account.items | save -f $account.out
      }

      # open the file for the user to edit
      soffice $account.out

      # read the results of the CSV file
      let updated_items = open $account.out

      # update the account
      $account
      | update items $updated_items
    }
    | get items
    | flatten
}

def verify_all_have_category [entry: record] {
  $entry.category | debug
  if $entry.category == "" {
    let msg = $"Entry missing category: ($entry)\nUse --retry to try again"
    error make $msg
  }

  $entry
}
