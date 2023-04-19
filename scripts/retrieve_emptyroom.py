#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Apr 18 2023

@author: Price Withers
"""

from argparse import ArgumentParser
from datetime import datetime
import os
from pathlib import Path
import requests
import shlex
import shutil
import subprocess
import sys

import mne.io
from mne_bids import BIDSPath, write_raw_bids

from colors import Colors

try:
    from bs4 import BeautifulSoup
except ModuleNotFoundError:
    print(
        Colors.RED,
        f"++ bs4 module not installed. Run `pip install beautifulsoup4` in mne environment, then re-run script.++",
        Colors.END
    )
    sys.exit(1)


def nearest(items, pivot):
    """Returns the datetime in items that is nearest to pivot."""

    datetime_items = [datetime.strptime(str(val), "%Y%m%d") for val in items]
    date_pivot = datetime.strptime(str(pivot), "%Y%m%d")
    closest_datetime = min(datetime_items, key=lambda x: abs(x - date_pivot))

    return int(closest_datetime.strftime("%Y%m%d"))


def retrieve_possibles(search_urls):

    possible_dates = []
    possible_urls = []
    for url in search_urls:

        # for zip files check if date is within one month
        if url.endswith(".tgz"):
            possible_dates.append(int(url.split("_")[2]))
            possible_urls.append(url)

    return possible_dates, possible_urls


def retrieve_urls(url_link):

    reqs = requests.get(url_link)
    soup = BeautifulSoup(reqs.text, "html.parser")
    urls = [
        url.get("href")
        for url in soup.find_all("a")
        if url.get("href").endswith((".tgz", ".html"))
    ]

    return urls


def download_and_unzip(url_link, output_dir):

    response = requests.get(url_link, stream=True)
    tgz_file = url_link.split("/")[-1]
    if response.status_code == 200:
        with open((output_dir / tgz_file), "wb") as f:
            f.write(response.raw.read())

    os.chdir(output_dir)
    cmd = shlex.split(f"tar -xvzf {output_dir / tgz_file}")
    subprocess.run(cmd)
    os.remove((output_dir / tgz_file))


if __name__ == "__main__":

    # parse arguments
    purpose = "download emptyroom recording with closest date to subject MEG session"
    parser = ArgumentParser(description=purpose)
    parser.add_argument("pnum", help="subject p-number")

    args = parser.parse_args()
    pnum = args.pnum

    neu_dir = Path("/Volumes/shares/NEU")
    bids_root = neu_dir / 'Data'
    emptyroom_dir = bids_root / 'sub-emptyroom'
    subj_meg_temp_dir = bids_root / f'sub-{pnum}' / 'temp'

    emptyroom_url = "https://kurage.nimh.nih.gov/EmptyRoom/"
    main_urls = retrieve_urls(emptyroom_url)
    possible_dates, possible_urls = retrieve_possibles(main_urls)

    goal_date = int(
        next(subj_meg_temp_dir.glob(f"*_epilepsy_????????_*.ds")).stem.split("_")[2]
    )

    best_date = nearest(possible_dates, goal_date)
    best_idx = possible_dates.index(best_date)
    best_url = possible_urls[best_idx]

    # if the best possible date is the last one, then must search other .htmls
    if best_idx == (len(possible_dates) - 1):
        month_goal = int(str(goal_date)[:-2])

        for url in main_urls:
            if url.endswith(".html"):

                # if month_url is within one of month_goal, then search into it
                if (abs(month_goal - int(url[:-5])) <= 1) or (main_urls[-1] == url):
                    sub_urls = retrieve_urls(f"{emptyroom_url}{url}")
                    possible_sub_dates, possible_sub_urls = retrieve_possibles(sub_urls)
                    best_sub_date = nearest(possible_sub_dates, goal_date)
                    best_sub_idx = possible_sub_dates.index(best_sub_date)

                    idx_choice = [best_date, best_sub_date].index(
                        nearest([best_date, best_sub_date], goal_date)
                    )

                    # previous was better
                    if idx_choice == 0:
                        break
                    else:
                        best_date = best_sub_date
                        best_url = possible_sub_urls[best_sub_idx]

    # check for existing files
    emptyroom_date_dir = emptyroom_dir / f'ses-{best_date}'
    temp_output_dir = emptyroom_dir / 'temp'
    if emptyroom_date_dir.exists():
        print(Colors.YELLOW, f"++ {pnum} already has Emptyroom data in {emptyroom_date_dir}++", Colors.END)
        sys.exit(1)
    else:
        temp_output_dir.mkdir(parents=True)
        download_and_unzip(
            url_link=f"{emptyroom_url}{best_url}", 
            output_dir=temp_output_dir
        )

    # check for existing files
    ds_list = list(temp_output_dir.glob("MEG_EmptyRoom*.ds"))
    if len(ds_list) == 0:
        print(Colors.RED, f"++ Emptyroom recording failed to download for {pnum} ++", Colors.END)
        sys.exit(1)
    
    ## convert files to bids format
    
    raw = mne.io.read_raw_ctf(
        directory=ds_list[0],
        preload=False
    )
    
    temp_bids_dir = bids_root / 'temp'
    bids_path = BIDSPath(
        subject='emptyroom',
        session=str(best_date),
        task='noise',
        root=temp_bids_dir
    )
    write_raw_bids(
        raw=raw,
        bids_path=bids_path
    )
    
    temp_ses_dir = temp_bids_dir / f'sub-emptyroom' / f'ses-{best_date}'
    temp_ses_dir.rename(emptyroom_date_dir)
    
    shutil.rmtree(temp_output_dir)
    shutil.rmtree(temp_bids_dir)