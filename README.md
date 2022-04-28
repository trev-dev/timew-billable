# timew-billable

A [Timewarrior](https://timewarrior.net/) report script that will help you organize your logged work time into structured projects with summarized billable hours. 

This project was inspired by the venerable Emacs org-mode and its built-in clock tables. The goal is to create some of those features for Timewarrior.

Requires Python >= 3.7

Version 0.1.0

*Note:* This is beta software. While it's only meant to read your data and should do you no harm, it comes with a disclaimer that it is provided as-is and you may use or hack it at your own risk.

Check back later for updates :)

## Contents

1. <a href="#start">Getting Started</a>
2. <a href="#config">Configuration</a>
3. <a href="#example">Example</a>
4. <a href="#future">Planned Features</a>

<div id="start"></div>

## Getting Started

1. Clone this repo onto your machine if you wish to keep it up-to-date with git. Or not. You do you.
2. Create a symlink to or copy whichever script you wish to use into your `~/.timewarrior/extensions/` folder.
3. Make sure the script is executable with `chmod +x <script-name>`.
4. Attempt to use it with `timew report <script-name>` or just `timew <script-name>`.

If you run into issues with running the script, open it up in your editor of choice and make sure the hash-bang reference to your Python executable is correct. Check `which python` in your command line if you're not sure where your python binary is located.

<div id="config"></div>

## Configuration

Timewarrior is super simple. It contains hardly any metadata, unlike its companion app, [ Taskwarrior](https://taskwarrior.org/).

While you may use this repo for Timewarrior alone, it's intended use is with Taskwarrior & the automatic Timewarrior modify hook. If you're not sure how to use Timewarrior & Taskwarrior together, [read the docs](https://timewarrior.net/docs/taskwarrior/).

In order to make things work correctly, we're going to need to embed our own metadata into your Task/Timewarrior data. This metadata can be adapted to your liking via the [Timewarrior configuration](https://timewarrior.net/docs/configuration/) file.

There is an [example config](./example.cfg) in this repository which contains the configuration defaults. It is meant to be used as a reference. It is not necessary to re-define the default configuration.

Here are the configuration options:  
* `billable` - Your default, billable rate as a float.  
  Default: `0.0`
* `billable.<client>` - Specify a separate billable rate tag for any given task/project.
* `billable.project_marker` - Specify a marker to flag the time entry as a project with a specific hierarchy.  
  Default: `#`
* `billable.separator` - Specify the character used to split a project hierarchy into its nested subtasks.  
  Default: `.`
* `billable.description_marker` - An optional marker for a task description. The first non-configuration or non-meta tag is used by default.

  **Timewarrior does not reinforce the order of your tags automatically**. If you struggle with their order by changing tags in Time/Taskwarrior, this configuration option is for you.
* `billable.locale` - Specify your locale for the purposes of formatting currency.

<div id="example"></div>

## Example

I have a web project for a client called "Wild Poppy" who sells "artisan flower arrangements." Said project has many dependant tasks which are:

- Make a homepage
- Make a navigation menu
- Make an order-form page

I would create my Taskwarrior entries as such:

`task add project:#WildPoppy.Website Make a homepage +WildPoppy`  
`task add project:#WildPoppy.Website Make a navigation menu +WildPoppy`  
(...etc)

I do some work for Wild Poppy, then at the end of the month I decide to invoice them.

When I run `timew billable :month WildPoppy` I get this:

```
Projects                       Time   Subtotals
===============================================
WildPoppy                      16.5   $1,320.00
— Website                      16.5   $1,320.00
—— Make a homepage              7.0     $560.00
—— Make a navigation menu       5.5     $440.00
—— Make an order-form page      4.0     $320.00
===============================================
Total                          16.5   $1,320.00
```

Maybe later on Wild Poppy gets really successful and has tons of work for me. We negotiate a special bulk-rate, separate from my usual rate. All I have to do is go into my configuration and add `billable.WildPoppy = 70' to give them a special rate.

The only limit to the nested hierarchy is your sanity :) You could do something like this:
`task add #Renovation.kitchen.sink Decide on which faucets to use +reno` and the report will nest and summarize it accordingly:

```
Projects                            Time   Subtotals
====================================================
Renovation                           1.0     $150.00
— kitchen                            1.0     $150.00
—— sink                              1.0     $150.00
———  Decide on which faucets to use  1.0     $150.00
====================================================
Total                               16.5     $150.00
```

<div id="future"></div>

## Planned Features

- [ ] Write Tests
- [ ] Add a more simple script for summarizing time spent instead of invoicing.
- [ ] Add a CSV export for any/all scripts.
- [ ] Add MarkDown table format for any/all scripts for easy PDF exports or TaskWiki usage.
- [ ] Refactor into pip module(?)
