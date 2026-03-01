# TODO MACOS

- [x] get buttons back to white
- [x] make bars actually round
- [ ] make bar & particle controls better
- [ ] make title controls better
- [ ] export as video



# TODO



- [ ] snap rotate (or at least type in an angle / go up and down by one degree or something)
- [ ] fix the rotate handle
- [ ] resize
- [ ] upload midi image
- [ ] play video
- [ ] video thumbnails
- [ ] bars
- [ ] find the piano & make the trapezoid rectangular
- [ ] actually fix dragging the image instead of the handles
- [ ] fix the drag and drop midi/mp3 stuff 
- [ ] overall ui redesign
- [ ] split up uploads

56.2%



```bash
ffmpeg -i attempt13_copy.mov -vf "scale=in_range=full:out_range=full" -color_range 2 -c:v libx264 -crf 18 fixed_input.mov
```

```
ffmpeg -i attempt13_copy.mov -vf zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p -c:v libx265 -crf 22 -preset medium -tune fastdecode attempt13_copy.mov
```

```
ffmpeg -i attempt13_copy.mov -vf zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p -c:v libx265 -crf 22 -preset medium -tune fastdecode attempt13_copy_sdr.mov
```

```
ffmpeg -i  attempt13_copy.mov -q:v 0  attempt13_copy.mp4
```